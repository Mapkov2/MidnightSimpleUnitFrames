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

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
    "hoehe", "breite", "kampf", "fadenkreuz", "profil", "aus",
}

local rawPhrases = {
    "spieler name aus",
    "target cast bar hoehe 24",
    "target castbar text groesse 14",
    "party health text groesse 12",
    "raid ready check icon aus",
    "class power aus",
    "kampf status aus",
    "fadenkreuz aus",
    "profil status",
    "kopiere party layout nach raid",
    "target buffs groesse 32",
    "focus power bar breite 180",
    "zeige castbar einstellungen",
    "set menu language to deutsch",
}

local bannedPhrases = {
    "Raid Group Frames are disabled",
    "Party Group Frames are disabled",
}

local cases = {
    { input = "spieler name aus", status = "applied", contains = "Player Name" },
    { input = "target cast bar hoehe 24", status = "applied", contains = "Target Castbar Height" },
    { input = "target castbar text groesse 14", status = "info", contains = "I found these MSUF matches" },
    { input = "party health text groesse 12", status = "applied", contains = "Party HP Font Size" },
    { input = "raid ready check icon aus", status = "unchanged", contains = "Raid Ready Check Icon" },
    { input = "class power aus", status = "applied", contains = "Class Resource" },
    { input = "kampf status aus", status = "unchanged", contains = "Combat Enter/Leave Text" },
    { input = "combat timer aus", status = "unchanged", contains = "Combat Timer" },
    { input = "fadenkreuz aus", status = "unchanged", contains = "Combat Crosshair" },
    { input = "profil status", status = "info", contains = "Active profile:" },
    { input = "kopiere player settings to target", status = "failed", contains = "Open a unit frame page first" },
    { input = "kopiere party layout nach raid", status = "applied", contains = "Party group-frame options to Raid" },
    { input = "target buffs groesse 32", status = "applied", contains = "Target Buff Icon Size" },
    { input = "focus power bar breite 180", status = "info", contains = "Focus Power Bar width" },
    { input = "boss frames columns 2", status = "ambiguous", contains = "I found multiple matches" },
    { input = "open auras", status = "navigated", contains = "Opened Target and focused Auras" },
    { input = "zeige castbar einstellungen", status = "ambiguous", contains = "Cast Bar" },
    { input = "where is class power", status = "navigated", contains = "Opened Class Resources" },
    { input = "where are group auras", status = "navigated", contains = "Opened Group Auras" },
    { input = "group text help", status = "info", contains = "Group Layout help" },
    { input = "what can i change in profiles", status = "info", contains = "Profiles help" },
    { input = "what can i change in colors", status = "info", contains = "Colors help" },
    { input = "what can i change in target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "what can i change in target debuffs", status = "info", contains = "Aura Debuffs help" },
    { input = "where can i change profiles", status = "info", contains = "Profiles help" },
    { input = "where can i change group health and text", status = "info", contains = "Group Layout help" },
    { input = "where can i change target health text", status = "info", contains = "Unit frame text help" },
    { input = "how do i chnage auara size", status = "info", contains = "Auras help" },
    { input = "what are auaras", status = "info", contains = "Auras, buffs, and debuffs help" },
    { input = "which page has raid ready check icons", status = "info", contains = "Group Status & Indicators help" },
    { input = "how do i change profiles", status = "info", contains = "Profiles help" },
    { input = "how do i set target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "how do i change castbar interrupt color", status = "info", contains = "Cast Bar interrupt color help" },
    { input = "which menu has profile export", status = "info", contains = "Profiles help" },
    { input = "what menu has target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "where should i go to change profiles", status = "info", contains = "Profiles help" },
    { input = "where do i manage target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "what controls castbar interrupt color", status = "info", contains = "Cast Bar interrupt color help" },
    { input = "what option changes target health text", status = "info", contains = "Unit frame text help" },
    { input = "what setting controls target powerbar offset", status = "info", contains = "Power Bar offset help" },
    { input = "tell me where profile export is", status = "info", contains = "Profiles help" },
    { input = "make my raid frames easier to read", status = "info", contains = "Group frame readability help" },
    { input = "raid frames are too busy", status = "info", contains = "Group frame readability help" },
    { input = "make target buffs easier to read", status = "info", contains = "Aura readability help" },
    { input = "make boss casts easier to track", status = "info", contains = "Cast bar readability help" },
    { input = "make player text easier to read", status = "info", contains = "Text readability help" },
    { input = "totem frame is gone", status = "info", contains = "Totem Frame" },
    { input = "alternative mana is missing", status = "info", contains = "Class Resources diagnostic" },
    { input = "target sound not working", status = "info", contains = "Target sound help" },
    { input = "minimap icon is missing", status = "unchanged", contains = "MSUF Minimap Icon" },
    { input = "tooltips not showing", status = "unchanged", contains = "Show Unit Frame Tooltips" },
    { input = "blizzard frames are still visible", status = "unchanged", contains = "Blizzard Unit Frames" },
    { input = "blizzard player frame still shows", status = "applied", contains = "Fully Hide Blizzard PlayerFrame" },
    { input = "menu language is wrong", status = "info", contains = "Menu language help" },
    { input = "welcome message keeps showing", status = "applied", contains = "Welcome Message" },
    { input = "version popup keeps showing", status = "applied", contains = "Peer Version Check" },
    { input = "snap menu to screen", status = "unchanged", contains = "Menu Edge Snap" },
    { input = "i cannot move frames", status = "info", contains = "Edit Mode troubleshooting help" },
    { input = "how do i move frames", status = "info", contains = "Edit Mode help" },
    { input = "grid not showing in edit mode", status = "info", contains = "Edit Mode grid help" },
    { input = "snap is not working in edit mode", status = "info", contains = "Edit Mode snap help" },
    { input = "previews not showing in edit mode", status = "info", contains = "Edit Mode Preview" },
    { input = "my settings are gone after reload", status = "info", contains = "Profile storage help" },
    { input = "profile string invalid", status = "info", contains = "Profile import help" },
    { input = "export my profile", status = "info", contains = "Profile backup and export help" },
    { input = "profile backup help", status = "info", contains = "Profile backup and export help" },
    { input = "copy my current profile", status = "info", contains = "Profile copy help" },
    { input = "profile switch not working", status = "info", contains = "Specialization profile help" },
    { input = "restore old profile", status = "info", contains = "Profile recovery help" },
    { input = "raid frames are in the wrong order", status = "info", contains = "Group sorting help" },
    { input = "raid frames are in one column", status = "info", contains = "Group columns help" },
    { input = "party frames grow the wrong way", status = "info", contains = "Group spacing and growth help" },
    { input = "raid frames are too far apart", status = "info", contains = "Group spacing and growth help" },
    { input = "click casting not working", status = "info", contains = "Mouseover and click casting help" },
    { input = "raid frames are not clickable", status = "info", contains = "Mouseover and click casting help" },
    { input = "raid frames too faded", status = "info", contains = "Group range fade help" },
    { input = "blizzard party frames show instead", status = "info", contains = "Blizzard group-frame fallback help" },
    { input = "target cast bar is in the wrong place", status = "info", contains = "Cast bar position help" },
    { input = "castbar not moving", status = "info", contains = "Cast bar position help" },
    { input = "castbar preview not working", status = "info", contains = "Cast bar preview help" },
    { input = "castbar icon is missing", status = "info", contains = "Cast bar text and icon help" },
    { input = "target debuffs are on wrong side", status = "info", contains = "Aura layout help" },
    { input = "buffs grow the wrong way", status = "info", contains = "Aura layout help" },
    { input = "anchro group frame buffs to the left", status = "applied", contains = "Party Buff Anchor" },
    { input = "buff filter not working", status = "info", contains = "Aura filter help" },
    { input = "blacklist spell not working", status = "info", contains = "Aura filter help" },
    { input = "only my buffs are showing", status = "info", contains = "Aura filter help" },
    { input = "aura cooldown text missing", status = "info", contains = "Aura text visibility help" },
    { input = "aura stack text missing", status = "info", contains = "Aura text visibility help" },
    { input = "health text shows wrong format", status = "info", contains = "Text format help" },
    { input = "player health text is missing", status = "info", contains = "Text visibility help" },
    { input = "target power bar wrong place", status = "info", contains = "Power bar position help" },
    { input = "power bar is missing", status = "info", contains = "Power bar visibility help" },
    { input = "class resources wrong position", status = "info", contains = "Class Resources position help" },
    { input = "class resources not moving", status = "info", contains = "Class Resources position help" },
    { input = "combo points wrong color", status = "info", contains = "Which Rogue / Feral Druid Combo Points color" },
    { input = "class resources preview not working", status = "info", contains = "Class Resources preview help" },
    { input = "combat timer wrong position", status = "info", contains = "Combat Timer position help" },
    { input = "combat timer not moving", status = "info", contains = "Combat Timer position help" },
    { input = "crosshair wrong color", status = "info", contains = "Combat Crosshair color help" },
    { input = "combat crosshair wrong size", status = "info", contains = "Combat Crosshair size help" },
    { input = "totem icons wrong position", status = "info", contains = "Totem Frame position help" },
    { input = "player frame wrong position", status = "info", contains = "Unit frame position help" },
    { input = "target frame not moving", status = "info", contains = "Unit frame position help" },
    { input = "focus frame wrong size", status = "info", contains = "Unit frame size help" },
    { input = "boss frames wrong position", status = "info", contains = "Unit frame position help" },
    { input = "target frame too faded", status = "info", contains = "Unit frame color and opacity help" },
    { input = "player portrait is missing", status = "info", contains = "Portrait help" },
    { input = "target portrait wrong style", status = "info", contains = "Portrait help" },
    { input = "portrait is wrong", status = "info", contains = "Portrait help" },
    { input = "raid marker wrong position", status = "info", contains = "Indicator position help" },
    { input = "role icon wrong position", status = "info", contains = "Indicator position help" },
    { input = "ready check icon wrong position", status = "info", contains = "Indicator position help" },
    { input = "leader icon missing", status = "info", contains = "Indicator visibility help" },
    { input = "resting icon missing", status = "info", contains = "Indicator visibility help" },
    { input = "pvp icon wrong position", status = "info", contains = "Indicator position help" },
    { input = "assistant is not answering", status = "info", contains = "Assistant matching help" },
    { input = "assistant does not understand me", status = "info", contains = "Assistant matching help" },
    { input = "assistant keeps giving search results", status = "info", contains = "Menu search help" },
    { input = "assistant answered in german", status = "info", contains = "Assistant language help" },
    { input = "assistant output is too long", status = "info", contains = "Assistant matching help" },
    { input = "chat box is too small", status = "info", contains = "Menu and Assistant size help" },
    { input = "menu is off screen", status = "info", contains = "Menu and Assistant size help" },
    { input = "menu search not working", status = "info", contains = "Menu search help" },
    { input = "search results are wrong", status = "info", contains = "Menu search help" },
    { input = "where is search", status = "navigated", contains = "Done. Opened Search." },
    { input = "undo not working", status = "info", contains = "Undo and history help" },
    { input = "redo not working", status = "info", contains = "Undo and history help" },
    { input = "how do i undo a change", status = "info", contains = "Undo and history help" },
    { input = "assistant history is missing", status = "info", contains = "Undo and history help" },
    { input = "support link not working", status = "info", contains = "Support link help" },
    { input = "discord link not working", status = "info", contains = "Support link help" },
    { input = "factory reset scares me", status = "info", contains = "Factory reset and recovery help" },
    { input = "i reset everything by accident", status = "info", contains = "Factory reset and recovery help" },
    { input = "run checks not working", status = "info", contains = "Checks and diagnostics help" },
    { input = "which one is safer", status = "info", contains = "Selection guidance" },
    { input = "which one should i use", status = "info", contains = "Selection guidance" },
    { input = "choose the best one", status = "info", contains = "Selection guidance" },
    { input = "do what you recommend", status = "info", contains = "Selection guidance" },
    { input = "explain like im new", status = "info", contains = "Simple explanation help" },
    { input = "why would i change this", status = "info", contains = "Simple explanation help" },
    { input = "is this safe", status = "info", contains = "Safety guidance" },
    { input = "will this break my profile", status = "info", contains = "Safety guidance" },
    { input = "i dont know what to choose", status = "info", contains = "Selection guidance" },
    { input = "can you undo later", status = "info", contains = "Safety guidance" },
    { input = "which settings are risky", status = "info", contains = "Safety guidance" },
    { input = "apply safe defaults", status = "info", contains = "Safe setup planning" },
    { input = "fix my ui automatically", status = "info", contains = "Safe setup planning" },
    { input = "give me a checklist", status = "info", contains = "native MSUF guided setup" },
    { input = "what should i check first", status = "info", contains = "native MSUF guided setup" },
    { input = "can you diagnose my ui", status = "info", contains = "Diagnostic planning" },
    { input = "make this less cluttered", status = "info", contains = "Clutter planning" },
    { input = "hide useless buffs", status = "info", contains = "Aura filter planning" },
    { input = "show important debuffs", status = "info", contains = "Aura filter planning" },
    { input = "optimize my ui for mythic plus", status = "info", contains = "Mythic+ and dungeon UI" },
    { input = "i want a healer ui", status = "info", contains = "Role setup guidance" },
    { input = "i want a minimal ui", status = "info", contains = "Minimal UI planning" },
    { input = "backup before changes", status = "info", contains = "Profile backup planning" },
    { input = "how do i make a backup", status = "info", contains = "Profile backup planning" },
    { input = "party frames vs raid frames", status = "info", contains = "Group frame comparison" },
    { input = "should i use party or raid frames", status = "info", contains = "Group frame comparison" },
    { input = "aura filters vs aura layout", status = "info", contains = "Aura system comparison" },
    { input = "which frame should show debuffs", status = "info", contains = "Aura placement planning" },
    { input = "i only want important info", status = "info", contains = "Information density planning" },
    { input = "reduce aura spam", status = "info", contains = "Information density planning" },
    { input = "can you explain your recommendation", status = "info", contains = "Information density planning" },
    { input = "do the first safe step", status = "info", contains = "Information density planning" },
    { input = "class resources vs power bar", status = "info", contains = "Resource bar comparison" },
    { input = "cast bar vs focus kick tracker", status = "info", contains = "Cast bar and kick tracker comparison" },
    { input = "target of target vs focus target", status = "info", contains = "Target-of-target and focus-target comparison" },
    { input = "boss frames vs target frame", status = "info", contains = "Boss and target frame comparison" },
    { input = "raid markers vs role icons", status = "info", contains = "Group indicator comparison" },
    { input = "absorb bar vs heal prediction", status = "info", contains = "Absorb and heal prediction comparison" },
    { input = "font outline vs font shadow", status = "info", contains = "Font outline and shadow comparison" },
    { input = "cooldown swipe vs cooldown text", status = "info", contains = "Aura text and cooldown comparison" },
    { input = "growth direction vs anchor", status = "info", contains = "Positioning option comparison" },
    { input = "menu scale vs ui scale", status = "info", contains = "Scale option comparison" },
    { input = "profile copy vs profile export", status = "info", contains = "Profile action comparison" },
    { input = "reset profile vs factory reset", status = "info", contains = "Profile action comparison" },
    { input = "edit mode vs unlock frames", status = "info", contains = "Edit Mode and unlock comparison" },
    { input = "blizzard frames vs msuf frames", status = "info", contains = "Blizzard and MSUF frame comparison" },
    { input = "unit frames vs group frames", status = "info", contains = "Unit and group frame comparison" },
    { input = "dispellable debuffs vs all debuffs", status = "info", contains = "Aura system comparison" },
    { input = "what should healers track", status = "info", contains = "Healer tracking guidance" },
    { input = "what should tanks track", status = "info", contains = "Tank tracking guidance" },
    { input = "why use target of target", status = "info", contains = "Why Target of Target matters" },
    { input = "why use aura filters", status = "info", contains = "Aura filters, in normal words" },
    { input = "my profile changed after switching spec", status = "info", contains = "Specialization profile help" },
    { input = "frames reset after relog", status = "info", contains = "Profile storage help" },
    { input = "show me profile options", status = "navigated", contains = "Opened Profiles" },
    { input = "show me target debuff options", status = "navigated", contains = "Opened Target and focused Aura Debuffs" },
    { input = "list raid ready check options", status = "info", contains = "Group Status & Indicators help" },
    { input = "list castbar interrupt color options", status = "info", contains = "Cast Bar interrupt color help" },
    { input = "i want to change profiles", status = "info", contains = "Profiles help" },
    { input = "i want to change target buffs", status = "ambiguous", contains = "Target Buffs - Target" },
    { input = "i want to configure raid ready check icons", status = "info", contains = "Group Status & Indicators help" },
    { input = "i want to change castbar interrupt colors", status = "ambiguous", contains = "Interruptible Cast Color" },
    { input = "i need raid ready check options", status = "info", contains = "Group Status & Indicators help" },
    { input = "help me find profile export", status = "info", contains = "Profiles help" },
    { input = "help me find target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "help me locate raid ready checks", status = "info", contains = "Group Status & Indicators help" },
    { input = "i am trying to change target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "i'm trying to change target debuffs", status = "info", contains = "Aura Debuffs help" },
    { input = "im trying to configure raid ready check icons", status = "info", contains = "Group Status & Indicators help" },
    { input = "i am looking for profile export", status = "info", contains = "Profiles help" },
    { input = "i'm looking for target buff options", status = "navigated", contains = "Aura Buffs help" },
    { input = "im looking for raid ready checks", status = "info", contains = "Group Status & Indicators help" },
    { input = "i need help with target buffs", status = "info", contains = "Aura Buffs help" },
    { input = "i need help with profile export", status = "info", contains = "Profiles help" },
    { input = "where are target buff options", status = "navigated", contains = "Opened Aura Buffs" },
    { input = "where are target debuff options", status = "navigated", contains = "Opened Aura Debuffs" },
    { input = "where are modules", status = "navigated", contains = "Opened Modules" },
    { input = "where is dashboard scaling", status = "navigated", contains = "Opened Dashboard scaling tools" },
    { input = "where is display recovery", status = "navigated", contains = "Opened Dashboard recovery tools" },
    { input = "where are support links", status = "navigated", contains = "MSUF support links" },
    { input = "where is changelog", status = "navigated", contains = "Opened Dashboard changelog" },
    { input = "search spell indicator growth", status = "info", contains = "Set Group Spell Indicator Aura" },
    { input = "search spell indicator anchor", status = "info", contains = "Group Status & Indicators" },
    { input = "search spell indicator tint alpha", status = "info", contains = "Set Group Spell Indicator Aura" },
    { input = "anchor class resources player power to class resource", status = "applied", contains = "Player Detached Power Bar Anchors to Class Resource" },
    { input = "sync class resources player power width", status = "unchanged", contains = "Player Detached Power Bar Syncs to Class Resource Width" },
    { input = "search class resources player power width", status = "info", contains = "Player Detached Power Bar Width" },
    { input = "search class resources player power bar texture", status = "info", contains = "Detached Power Bar Foreground Texture" },
    { input = "set class resources player power width to 300", status = "applied", contains = "Player Detached Power Bar Width" },
    { input = "i want to change target width to 300", status = "applied", contains = "Target Width" },
    { input = "i am trying to change target width to 300", status = "unchanged", contains = "Target Width" },
    { input = "search unit text slot", status = "info", contains = "HP Center Slot" },
    { input = "search unit text slot x", status = "info", contains = "Slot X Offset" },
    { input = "search unit text size", status = "info", contains = "HP Font Size" },
    { input = "search global font outline", status = "info", contains = "Shared Font Outline" },
    { input = "search global font monochrome", status = "info", contains = "Shared Rendering" },
    { input = "search shared font shadow strength", status = "info", contains = "Shared Shadow Strength" },
    { input = "search global bar right absorb", status = "info", contains = "Absorb Bar Anchor" },
    { input = "search global bar absorb color", status = "info", contains = "Absorb Bar Color" },
    { input = "search global bar right color", status = "info", contains = "Bar Gradient Direction" },
    { input = "search party ready check anchor", status = "info", contains = "Party Ready Check Icon Anchor" },
    { input = "search raid role icon x offset", status = "info", contains = "Raid Role Icon X Offset" },
    { input = "search group indicator test mode", status = "info", contains = "Preview Group Status Icon" },
    { input = "search group raid marker indicator size", status = "info", contains = "Raid Marker Size" },
    { input = "search raid frame scaling", status = "info", contains = "Raid Frame Scaling - Group Layout" },
    { input = "search raid scale 20 players", status = "info", contains = "Raid Scale 11-20 Players - Group Layout" },
    { input = "search anchor raid frames to player", status = "info", contains = "Raid Anchor to - Group Layout" },
    { input = "search party blizzard fallback", status = "info", contains = "Party Blizzard Fallback Mode - Group Layout" },
    { input = "search raid background color", status = "ambiguous", contains = "Raid Backdrop Color - Group Layout" },
    { input = "set menu language to german", status = "applied", contains = "German (deDE)" },
    { input = "set menu language to deutsch", status = "unchanged", contains = "German (deDE)" },
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
    for _, phrase in ipairs(bannedPhrases) do
        assert(not tostring(output or ""):find(phrase, 1, true), label .. ": output contains banned route phrase " .. phrase .. ": " .. tostring(output))
    end
    assert(not tostring(output or ""):lower():find("de de", 1, true), label .. ": output contains unfriendly locale label de de: " .. tostring(output))
end

local function checkPanel(label)
    local panel = A.largeTextPanel
    if type(panel) ~= "table" then return end
    assertEnglishOutput(label .. " panel title", panel.title or "")
    assertEnglishOutput(label .. " panel help", panel.help or "")
    assertEnglishOutput(label .. " panel status", panel.status or "")
    assertEnglishOutput(label .. " panel text", panel.text or "")
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
end

-- assistant_dashboard_smoke intentionally exercises this toggle and leaves it
-- disabled. Prime the first mutation case so its output proves a real change,
-- rather than depending on a previous smoke test's final state.
_G.MSUF_DB.player.showName = true

for _, case in ipairs(cases) do
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    local result = A.Submit(case.input)
    assert(type(result) == "table", case.input .. ": missing result")
    local status = result.status or result.result
    assert(status == case.status, case.input .. ": expected " .. tostring(case.status) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(case.input, result.text or "")
    assert(tostring(result.text or ""):find(case.contains, 1, true), case.input .. ": missing text " .. tostring(case.contains) .. ": " .. tostring(result.text or ""))
    checkPanel(case.input)
end

_G.MSUF2.activeKey = "gf_auras"
_G.MSUF2.gfScope = "raid"
local groupAuraContextCases = {
    { input = "make buff icons bigger", contains = "Raid Buff Icon Size" },
    { input = "set buff icon size to 24", contains = "Raid Buff Icon Size" },
    { input = "turn off debuffs", contains = "Raid Debuffs" },
    { input = "set debuff filter to dispellable", contains = "Raid Debuff Filter" },
}

for _, case in ipairs(groupAuraContextCases) do
    local result = A.Submit(case.input)
    assert(type(result) == "table", "group aura context " .. case.input .. ": missing result")
    assertEnglishOutput("group aura context " .. case.input, result.text or "")
    assert(tostring(result.text or ""):find(case.contains, 1, true), "group aura context " .. case.input .. ": missing text " .. tostring(case.contains) .. ": " .. tostring(result.text or ""))
end

io.write("assistant_command_surface_output_audit: ok cases=" .. tostring(#cases) .. " groupAuraContext=" .. tostring(#groupAuraContextCases) .. "\n")
