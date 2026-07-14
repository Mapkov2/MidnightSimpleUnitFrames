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

-- The production addon always provides the Auras3 MenuModel before the LoD
-- Assistant can be opened. The headless dashboard stub has only RequestApply,
-- so supply the small stateful contract used by filter-setting transactions.
local auraModelState = {}
local function auraScope(scope)
    scope = tostring(scope or "shared")
    auraModelState[scope] = auraModelState[scope] or { useSharedRules = true, filtersEnabled = true, filters = {} }
    return auraModelState[scope]
end
_G.MSUF_NS.MSUF_Auras3 = _G.MSUF_NS.MSUF_Auras3 or {}
_G.MSUF_NS.MSUF_Auras3.MenuModel = {
    UseSharedRules = function(scope) return auraScope(scope).useSharedRules end,
    SetUseSharedRules = function(scope, value) auraScope(scope).useSharedRules = value == true end,
    ScopeFiltersEnabled = function(scope) return auraScope(scope).filtersEnabled end,
    SetScopeFiltersEnabled = function(scope, value) auraScope(scope).filtersEnabled = value == true end,
    ReadFilter = function(scope, lane, key, defaultValue)
        local filters = auraScope(scope).filters
        local id = tostring(lane) .. "." .. tostring(key)
        local value = filters[id]
        return value == nil and defaultValue or value
    end,
    WriteFilter = function(scope, lane, key, value)
        auraScope(scope).filters[tostring(lane) .. "." .. tostring(key)] = value
    end,
    Apply = function() return true end,
}

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
    "hoehe", "breite", "kampf", "fadenkreuz", "profil", "aus",
}

local rawPhrases = {
    "where can i turn off the moon icon from player frame",
    "disable skull marker on target frame",
    "can i turn off the moon icon on player frame",
    "help me find the pvp icon on target frame",
    "is there a way to hide the elite icon on target frame",
    "can i turn off target buffs",
    "show me target debuff options",
    "can i disable target castbar",
    "can i make raid frames wider",
    "where can i turn off party click casting",
    "can i hide player name text",
    "can i turn off target power text",
    "can i detach target power bar",
    "can i hide combo points",
    "can i make class resources wider",
    "can i hide combat timer",
    "can i make combat crosshair bigger",
    "cap player auaras at 2",
    "can yu move my player frame",
    "make player hp txt bigger",
    "make target buff cooldown txt bigger",
    "make target combat status icn smaller",
    "make target pwr txt bigger",
    "move party readycheck up",
    "hide player raidmark",
    "make target aura cd txt bigger",
    "make raid debuf cd text bigger",
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

local function checkPanel(label)
    local panel = A.largeTextPanel
    if type(panel) ~= "table" then return end
    assertEnglishOutput(label .. " panel title", panel.title or "")
    assertEnglishOutput(label .. " panel help", panel.help or "")
    assertEnglishOutput(label .. " panel status", panel.status or "")
    assertEnglishOutput(label .. " panel text", panel.text or "")
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
end

local function dbValue(path)
    local node = _G.MSUF_DB
    for i = 1, #path do
        if type(node) ~= "table" then return nil end
        node = node[path[i]]
    end
    return node
end

local function clearAssistantState()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    A.pendingConfirmation = nil
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingFlow = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        for key in pairs(ctx) do ctx[key] = nil end
    end
end

local function listHas(list, phrase)
    for _, value in ipairs(list or {}) do
        if tostring(value):find(phrase, 1, true) then return true end
    end
    return false
end

local function expectedSemanticStatus(case)
    if case.status ~= "applied" then return case.status end
    local input = tostring(case.input or ""):lower()
    local readOnly = case.unchanged ~= nil
        or listHas(case.notContains, "Done. I changed")
        or input == "run checks"
        or input:match("^diagnos") ~= nil
        or input:match("^check%s+") ~= nil
        or input:match("^why%s+") ~= nil
        or input:match("^can you fix%s+") ~= nil
    if not readOnly then return case.status end
    if listHas(case.contains, "Opened ") or listHas(case.contains, "Done. Opened") then return "navigated" end
    return "info"
end

local function assertContains(label, output, phrases)
    for _, phrase in ipairs(phrases or {}) do
        assert(tostring(output or ""):find(phrase, 1, true), label .. ": missing text " .. tostring(phrase) .. ": " .. tostring(output))
    end
end

local function assertNotContains(label, output, phrases)
    for _, phrase in ipairs(phrases or {}) do
        assert(not tostring(output or ""):find(phrase, 1, true), label .. ": unexpected text " .. tostring(phrase) .. ": " .. tostring(output))
    end
end

local cases = {
    {
        input = "where can I turn off the moon icon from player frame?",
        status = "applied",
        contains = { "Raid Marker setting location", "Player Raid Marker" },
        notContains = { "Done. I changed", "Target Frame Enabled" },
        unchanged = { "player", "showRaidMarker" },
    },
    {
        input = "can I turn off the moon icon on player frame?",
        status = "applied",
        contains = { "Raid Marker setting location", "Player Raid Marker" },
        notContains = { "Done. I changed" },
        unchanged = { "player", "showRaidMarker" },
    },
    {
        input = "turn off moon icon from player frame",
        status = "applied",
        contains = { "Player Raid Marker" },
        notContains = { "Player Frame Enabled" },
        equals = { "player", "showRaidMarker", false },
    },
    {
        input = "disable skull marker on target frame",
        status = "applied",
        contains = { "Target Raid Marker" },
        notContains = { "Target Frame Enabled" },
        equals = { "target", "showRaidMarker", false },
    },
    {
        input = "can you show me the target of target name on the target frame?",
        status = "applied",
        contains = { "Target Target Inline Text", "enabled" },
        notContains = { "Opened Target of Target", "Target of Target Frame Enabled" },
        equals = { "targettarget", "showToTInTargetName", true },
    },
    {
        input = "hide target's target name on target frame",
        status = "applied",
        contains = { "Target Target Inline Text", "disabled" },
        notContains = { "Target Name from", "Target of Target Name is already", "Opened Target of Target" },
        equals = { "targettarget", "showToTInTargetName", false },
    },
    {
        input = "can you display target of target name on target?",
        status = "applied",
        contains = { "Target Target Inline Text", "enabled" },
        notContains = { "Target Name from", "Target of Target Name is already", "Opened Target of Target" },
        equals = { "targettarget", "showToTInTargetName", true },
    },
    {
        input = "hide targets target name on target frame",
        status = "applied",
        contains = { "Target Target Inline Text", "disabled" },
        notContains = { "Target Name from", "Target of Target Name is already", "Opened Target of Target" },
        equals = { "targettarget", "showToTInTargetName", false },
    },
    {
        input = "enable ToT name inside target frame",
        status = "applied",
        contains = { "Target Target Inline Text", "enabled" },
        notContains = { "Target Name from", "Target of Target Name is already", "Opened Target of Target" },
        equals = { "targettarget", "showToTInTargetName", true },
    },
    {
        input = "can you show target's target health text on target frame?",
        status = "info",
        contains = { "Cross-frame text clarification", "does not expose separate inline Target of Target health, power, or font-size controls" },
        notContains = { "Done. I changed", "Target HP Text", "Target Name from" },
        unchanged = { "target", "showHP" },
    },
    {
        input = "show targets target power text on target frame",
        status = "info",
        contains = { "Cross-frame text clarification", "does not expose separate inline Target of Target health, power, or font-size controls" },
        notContains = { "Done. I changed", "Target Power Text", "Target Name from" },
        unchanged = { "target", "showPower" },
    },
    {
        input = "make target's target name bigger on target frame",
        status = "info",
        contains = { "Cross-frame text clarification", "does not expose separate inline Target of Target health, power, or font-size controls" },
        notContains = { "Done. I changed", "Target Name Font Size", "Target of Target Name Font Size" },
        unchanged = { "target", "nameFontSize" },
    },
    {
        input = "where can I show the target of target name on the target frame?",
        status = "applied",
        contains = { "Target Target Inline Text setting location", "Target", "I did not change it" },
        notContains = { "Target of Target Custom Anchor Frame", "Done. I changed", "Unit Frames help" },
        unchanged = { "targettarget", "showToTInTargetName" },
    },
    {
        input = "where can I show target's target name on target frame?",
        status = "applied",
        contains = { "Target Target Inline Text setting location", "Target", "I did not change it" },
        notContains = { "Target Castbar Spell Name", "Done. I changed", "Unit Frames help" },
        unchanged = { "targettarget", "showToTInTargetName" },
    },
    {
        input = "where can I turn off target of target name on target frame?",
        status = "applied",
        contains = { "Target Target Inline Text setting location", "Target", "I did not change it" },
        notContains = { "Target of Target Custom Anchor Frame", "Done. I changed", "Unit Frames help" },
        unchanged = { "targettarget", "showToTInTargetName" },
    },
    {
        input = "why is my target frame missing target of target?",
        status = "info",
        contains = { "Target of Target visibility help", "Target Target Inline Text", "I did not change anything" },
        notContains = { "Target Absorb Bar Anchor", "Done. I changed" },
        unchanged = { "targettarget", "showToTInTargetName" },
    },
    {
        input = "my target of target name is missing",
        status = "info",
        contains = { "Target of Target visibility help", "Target of Target Name", "I did not change anything" },
        notContains = { "Target Absorb Bar Anchor", "Done. I changed" },
        unchanged = { "targettarget", "showName" },
    },
    {
        input = "why is focus frame missing focus target?",
        status = "info",
        contains = { "Focus Target visibility help", "separate MSUF frame", "I did not change anything" },
        notContains = { "Focus HP Center Slot", "Done. I changed" },
        unchanged = { "focustarget", "showName" },
    },
    {
        input = "can you show target name on player frame?",
        status = "info",
        contains = { "Cross-frame text clarification", "Target name text belongs to the Target frame", "Player text belongs to the Player frame" },
        notContains = { "Done. I changed", "Player Name from", "Target Name from" },
        unchanged = { "target", "showName" },
    },
    {
        input = "where can I show target name on player frame?",
        status = "info",
        contains = { "Cross-frame text clarification", "Target name text belongs to the Target frame", "Player text belongs to the Player frame" },
        notContains = { "Target Anchor Point", "Done. I changed" },
        unchanged = { "target", "showName" },
    },
    {
        input = "show player name on target frame",
        status = "info",
        contains = { "Cross-frame text clarification", "Player name text belongs to the Player frame", "Target text belongs to the Target frame" },
        notContains = { "Done. I changed", "Player Name from", "Target Name from" },
        unchanged = { "player", "showName" },
    },
    {
        input = "show target health text on player frame",
        status = "info",
        contains = { "Cross-frame text clarification", "Target health text belongs to the Target frame", "show target health text" },
        notContains = { "Done. I changed", "Player HP Text", "Target HP Text:" },
        unchanged = { "target", "showHP" },
    },
    {
        input = "show target castbar on player frame",
        status = "info",
        contains = { "Cross-frame visual clarification", "Target cast bar is frame-specific", "I did not change" },
        notContains = { "Done. I changed", "Already set", "Player Cast Bar" },
    },
    {
        input = "show target buffs on player frame",
        status = "info",
        contains = { "Cross-frame visual clarification", "Target buffs are frame-specific", "I did not change" },
        notContains = { "Done. I changed", "Already set", "Player Buffs from" },
    },
    {
        input = "where can I show target buffs on player frame?",
        status = "info",
        contains = { "Cross-frame visual clarification", "Target buffs are frame-specific", "I did not change" },
        notContains = { "Done. I changed", "Already set", "Player Buffs setting location" },
    },
    {
        input = "show target raid marker on player frame",
        status = "info",
        contains = { "Cross-frame visual clarification", "Target raid marker icon is frame-specific", "I did not change" },
        notContains = { "Done. I changed", "Already set", "Player Raid Marker" },
        unchanged = { "player", "showRaidMarker" },
    },
    {
        input = "show target portrait on player frame",
        status = "info",
        contains = { "Cross-frame visual clarification", "Target portrait is frame-specific", "I did not change" },
        notContains = { "Done. I changed", "Already set", "Player Portrait" },
    },
    {
        input = "show focus target name on focus frame",
        status = "info",
        contains = { "Cross-frame text clarification", "Focus Target has its own frame", "does not expose separate inline Focus Target text" },
        notContains = { "Done. I changed", "Focus Target Name from" },
        unchanged = { "focustarget", "showName" },
    },
    {
        input = "can you make target of target name bigger on target frame?",
        status = "info",
        contains = { "Cross-frame text clarification", "inline Target Target text option", "does not expose separate inline Target of Target health, power, or font-size controls" },
        notContains = { "Done. I changed", "Target Name Font Size", "Target of Target Name Font Size from" },
        unchanged = { "targettarget", "nameFontSize" },
    },
    {
        input = "can you show target of target castbar?",
        status = "info",
        contains = { "Target of Target cast bar help", "does not have its own separate cast bar toggle", "Player, Target, Focus, and Boss" },
        notContains = { "Done. I changed", "I found that option", "Opened Target of Target" },
    },
    {
        input = "where is target of target castbar?",
        status = "applied",
        contains = { "Target of Target cast bar help", "does not have its own separate cast bar toggle", "Open Cast Bars" },
        notContains = { "Done. I changed", "I found that option" },
    },
    {
        input = "can you move target of target below target?",
        status = "applied",
        contains = { "Target of Target Anchor to", "target" },
        notContains = { "I changed Target Anchor", "Target Frame Enabled" },
        equals = { "targettarget", "anchorToUnitframe", "target" },
    },
    {
        input = "where can I hide the leader icon on player frame?",
        status = "applied",
        contains = { "Leader/Assist Icon setting location", "Player Leader/Assist Icon" },
        notContains = { "Done. I changed" },
        unchanged = { "player", "showLeaderIcon" },
    },
    {
        input = "where can I disable the pvp icon on target frame?",
        status = "applied",
        contains = { "PvP Flag Indicator setting location", "Target PvP Flag Indicator" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showPvpIndicator" },
    },
    {
        input = "help me find the pvp icon on target frame",
        status = "applied",
        contains = { "PvP Flag Indicator setting location", "Target PvP Flag Indicator" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showPvpIndicator" },
    },
    {
        input = "where can I hide the elite icon on target frame?",
        status = "applied",
        contains = { "Elite / Rare Icon setting location", "Target Elite / Rare Icon" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showEliteIcon" },
    },
    {
        input = "is there a way to hide the elite icon on target frame?",
        status = "applied",
        contains = { "Elite / Rare Icon setting location", "Target Elite / Rare Icon" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showEliteIcon" },
    },
    {
        input = "where can I turn off ready check icon on raid frames?",
        status = "applied",
        contains = { "Ready Check for Party, Raid, and Mythic Raid frames", "Group Status & Indicators" },
        notContains = { "Done. I changed" },
    },
    {
        input = "which page has raid ready check icons",
        status = "applied",
        contains = { "Group Status & Indicators help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "how do I hide the resting icon on my frame?",
        status = "applied",
        contains = { "Rested Indicator setting location", "Player Rested Indicator" },
        notContains = { "Done. I changed" },
        unchanged = { "player", "showRestingIndicator" },
    },
    {
        input = "where can I remove the rez icon on target frame?",
        status = "applied",
        contains = { "Incoming Rez Indicator setting location", "Target Incoming Rez Indicator" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showIncomingResIndicator" },
    },
    {
        input = "where can I turn off target buffs?",
        status = "applied",
        contains = { "Target Buffs setting location", "Aura Buffs help", "Target Buffs" },
        notContains = { "Done. I changed", "Shared Show Buffs" },
    },
    {
        input = "can I turn off target buffs?",
        status = "applied",
        contains = { "Target Buffs setting location", "Aura Buffs help", "Target Buffs" },
        notContains = { "Done. I changed", "Shared Show Buffs" },
    },
    {
        input = "can I turn off Alternative Mana Bar?",
        status = "applied",
        contains = { "Alternative Mana Bar setting location", "Class Resources", "I did not change it" },
        notContains = { "Already set", "Done. I changed" },
    },
    {
        input = "is there a way to hide Alternative Mana Bar?",
        status = "applied",
        contains = { "Alternative Mana Bar setting location", "Class Resources", "I did not change it" },
        notContains = { "Already set", "Done. I changed" },
    },
    {
        input = "can I show Alternative Mana Bar?",
        status = "applied",
        contains = { "Alternative Mana Bar setting location", "Class Resources", "I did not change it" },
        notContains = { "Already set", "Done. I changed" },
    },
    {
        input = "turn off target buffs",
        status = "applied",
        contains = { "Target Buffs" },
        notContains = { "Shared Show Buffs" },
    },
    {
        input = "turn off target debuffs",
        status = "applied",
        contains = { "Target Debuffs" },
        notContains = { "Shared Show Debuffs" },
    },
    {
        input = "show me target debuff options",
        status = "applied",
        contains = { "Opened Target", "focused Aura Debuffs" },
        notContains = { "Done. I changed", "Shared Show Debuffs" },
    },
    {
        input = "where can I make target buff icons bigger?",
        status = "applied",
        contains = { "Target Buff Icon Size setting location", "Aura Buffs help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "how do I move target debuffs to the other side?",
        status = "applied",
        contains = { "Target Debuff Layout setting location", "Aura Debuffs help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can you hide moon icon on player buffs?",
        status = "info",
        contains = { "Player Buff specific icon filter", "not the whole Player Buffs lane", "Give me its SpellID", "identity filtering" },
        notContains = { "Done. I changed", "Player Buffs from", "Shared Show Buffs" },
    },
    {
        input = "where can I hide moon icon on player buffs?",
        status = "applied",
        contains = { "Player Buff specific icon filter", "Open Aura Filters", "set player buff raid filter on" },
        notContains = { "Done. I changed", "Player Buffs setting location", "Shared Show Buffs" },
    },
    {
        input = "can you hide power word shield on player frame?",
        status = "info",
        contains = { "add an exact SpellID exclusion", "I did not change the frame" },
        notContains = { "Player Power Right Slot", "Player Bar Gradient", "Done. I changed" },
    },
    {
        input = "where can I hide power word shield on player frame?",
        status = "applied",
        contains = { "Player hidden aura setting location", "Aura Filters", "I did not change the frame or its power text" },
        notContains = { "Player Power Right Slot", "Player Bar Gradient", "Done. I changed" },
    },
    {
        input = "where can I hide spell 17 from player buffs?",
        status = "applied",
        contains = { "Player Buff hidden aura setting location", "Aura Filters", "set player buff raid filter on" },
        notContains = { "Player Buffs setting location", "Done. I changed", "Shared Show Buffs" },
    },
    {
        input = "can you show only my buffs on target frame?",
        status = "applied",
        contains = { "Target Buffs now show only buffs cast by you", "Target Buff Player Filter is enabled" },
        notContains = { "Target Buffs from", "Shared Show Buffs" },
    },
    {
        input = "show only my debuffs on target frame",
        status = "applied",
        contains = { "Target Debuff Player Filter", "enabled" },
        notContains = { "Target Debuffs from", "Shared Show Debuffs" },
    },
    {
        input = "hide target debuff stack text",
        status = "applied",
        contains = { "Target Debuff Show Stack Count", "disabled" },
        notContains = { "Target Debuffs from", "Shared Show Debuffs" },
    },
    {
        input = "where can I hide target debuff stack text?",
        status = "applied",
        contains = { "Target Debuff Stack Count setting location", "separate from hiding the entire Debuffs lane" },
        notContains = { "Target Debuffs setting location", "Done. I changed" },
    },
    {
        input = "can you turn off cooldown swipe on target buffs?",
        status = "applied",
        contains = { "Target Buff Show Cooldown Swipe", "disabled" },
        notContains = { "Target Buffs from", "Shared Show Buffs" },
    },
    {
        input = "where can I turn off cooldown swipe on target buffs?",
        status = "applied",
        contains = { "Target Buff Cooldown Swipe setting location", "separate from hiding the entire Buffs lane" },
        notContains = { "Target Buffs setting location", "Done. I changed" },
    },
    {
        input = "show only dispellable debuffs on raid frames",
        status = "applied",
        contains = { "Raid Debuff Filter", "dispellable" },
        notContains = { "Raid Debuffs from", "Shared Show Debuffs" },
    },
    {
        input = "where can I show only dispellable debuffs on raid frames?",
        status = "applied",
        contains = { "Raid Debuff Dispellable Filter setting location", "Group Auras", "set raid debuff filter to dispellable" },
        notContains = { "Raid Debuffs setting location", "Done. I changed" },
    },
    {
        input = "hide raid buffs but keep debuffs",
        status = "applied",
        contains = { "Raid Buffs", "disabled" },
        notContains = { "Raid Debuffs from", "Shared Show Debuffs" },
    },
    {
        input = "where can I turn off target cast bar?",
        status = "applied",
        contains = { "Target Cast Bar setting location", "Cast Bars" },
        notContains = { "Done. I changed", "Target Frame Enabled" },
    },
    {
        input = "can I disable target castbar?",
        status = "applied",
        contains = { "Target Cast Bar setting location", "Cast Bars" },
        notContains = { "Done. I changed", "Target Frame Enabled" },
    },
    {
        input = "turn off target castbar",
        status = "applied",
        contains = { "Target Cast Bar" },
        notContains = { "Target Frame Enabled" },
    },
    {
        input = "where can I hide the target castbar icon?",
        status = "applied",
        contains = { "Target Castbar Icon setting location", "Cast Bars" },
        notContains = { "Done. I changed", "Target Frame Enabled" },
    },
    {
        input = "how do I make raid frames wider?",
        status = "applied",
        contains = { "Raid Width setting location", "Group Layout" },
        notContains = { "Done. I changed", "Raid X Position", "Raid Y Position" },
    },
    {
        input = "can I make raid frames wider?",
        status = "applied",
        contains = { "Raid Width setting location", "Group Layout" },
        notContains = { "Done. I changed", "Raid X Position", "Raid Y Position" },
    },
    {
        input = "make raid frames wider",
        status = "applied",
        contains = { "Raid Width" },
        notContains = { "Raid X Position", "Raid Y Position" },
    },
    {
        input = "where can I set raid frames to 5 columns?",
        status = "applied",
        contains = { "Raid Max Columns setting location", "Group Layout" },
        notContains = { "Done. I changed" },
    },
    {
        input = "where can I turn off party click casting?",
        status = "applied",
        contains = { "Party Click Casting setting location", "Group Layout" },
        notContains = { "Done. I changed" },
    },
    {
        input = "turn off party click cast",
        status = "applied",
        contains = { "Party Click Casting" },
    },
    {
        input = "where can I hide player name text?",
        status = "applied",
        contains = { "Player Name Text setting location", "Unit frame text help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I hide player name text?",
        status = "applied",
        contains = { "Player Name Text setting location", "Unit frame text help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "how do I hide player name?",
        status = "applied",
        contains = { "Player Name Text setting location", "Unit frame text help", "turn off player name text" },
        notContains = { "Boss Anchor Point", "Done. I changed" },
        unchanged = { "player", "showName" },
    },
    {
        input = "how do I show player name?",
        status = "applied",
        contains = { "Player Name Text setting location", "Unit frame text help", "turn on player name text" },
        notContains = { "Boss Anchor Point", "Done. I changed" },
        unchanged = { "player", "showName" },
    },
    {
        input = "hide player name text",
        status = "applied",
        contains = { "Player Name" },
    },
    {
        input = "where can I change target health text format?",
        status = "applied",
        contains = { "Target Health Text Format setting location", "Unit frame text help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I turn off target power text?",
        status = "applied",
        contains = { "Target Power Text setting location", "Unit frame text help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "how do I disable target power bar?",
        status = "applied",
        contains = { "Target Power Bar setting location", "Power Bar help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "where can I detach target power bar?",
        status = "applied",
        contains = { "Target Detach Power Bar from Frame setting location", "Power Bar help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "hide target power text",
        status = "applied",
        contains = { "Target Power Text" },
    },
    {
        input = "can you help me to move the target power text",
        status = "ambiguous",
        contains = { "Target Power Text X Offset", "Target Power Text Y Offset", "left or right", "up or down" },
        notContains = { "Unit frame text help", "Done. I changed" },
        unchanged = { "target", "powerOffsetY" },
    },
    {
        input = "can you help me to move the target power text?",
        status = "ambiguous",
        contains = { "Target Power Text X Offset", "Target Power Text Y Offset", "down 5" },
        notContains = { "Unit frame text help", "Done. I changed" },
        unchanged = { "target", "powerOffsetX" },
    },
    {
        input = "help me move target power text left",
        status = "applied",
        contains = { "Target Power Text X Offset" },
        notContains = { "Target Power Font Size", "Unit frame text help" },
    },
    {
        input = "could you help me move target power text up 5",
        status = "applied",
        contains = { "Target Power Text Y Offset" },
        notContains = { "Target Power Font Size", "Unit frame text help" },
    },
    {
        input = "I want the target power text a bit lower",
        status = "applied",
        contains = { "Target Power Text Y Offset" },
        notContains = { "Target Power Font Size", "Unit frame text help" },
    },
    {
        input = "how do I move target power text",
        status = "info",
        contains = { "Target Power Text X Offset", "Target Power Text Y Offset", "I kept it unchanged" },
        notContains = { "Unit frame text help", "Done. I changed" },
        unchanged = { "target", "powerOffsetY" },
    },
    {
        input = "can you help me find target power text x offset",
        status = "info",
        contains = { "Target Power Text X Offset", "left or right", "I kept it unchanged" },
        notContains = { "Target Power Text Y Offset", "Unit frame text help", "Done. I changed" },
        unchanged = { "target", "powerOffsetX" },
    },
    {
        input = "5",
        pre = { "set target power text y offset to 0", "change target power text y offset" },
        status = "applied",
        contains = { "Target Power Text Y Offset", "to 5" },
        notContains = { "result 5", "Which listed option" },
        equals = { "target", "powerOffsetY", 5 },
    },
    {
        input = "-5",
        pre = { "set target power text y offset to 0", "change target power text y offset" },
        status = "applied",
        contains = { "Target Power Text Y Offset", "to -5" },
        notContains = { "Which listed option" },
        equals = { "target", "powerOffsetY", -5 },
    },
    {
        input = "red",
        pre = { "change target bar outline color" },
        status = "applied",
        contains = { "Target Bar Outline Color", "#FF0000" },
        notContains = { "Which listed option" },
    },
    {
        input = "change target width to 300",
        pre = {
            "set target width to 282",
            "change class resource foreground texture",
        },
        status = "applied",
        contains = { "Target Width", "300" },
        notContains = { "Class Resource Foreground Texture from" },
        preserves = { "bars", "classPowerTexture" },
        equals = { "target", "width", 300 },
    },
    {
        input = "can you help me change player portrait to 2D",
        status = "applied",
        contains = { "Player Portrait Render", "2d" },
        notContains = { "Pick the control", "Player Portrait Position" },
    },
    {
        input = "move player buffs",
        status = "ambiguous",
        contains = { "Player Buff Growth", "Player Buff X Offset", "Player Buff Y Offset", "kept everything unchanged" },
        notContains = { "changed Player Buffs from", "Unit frame text help" },
        unchanged = { "auras3", "player", "buff", "enabled" },
    },
    {
        input = "help me move target portrait",
        status = "ambiguous",
        contains = { "Target Portrait X Offset", "Target Portrait Y Offset", "kept everything unchanged" },
        notContains = { "Focus Target Class Portrait Style", "Done. I changed" },
    },
    {
        input = "can you help me to change player buff grow direction",
        status = "ambiguous",
        contains = { "Player Buff Growth", "right then down", "left then up", "down" },
        notContains = { "Best place to start", "Aura Style" },
    },
    {
        input = "help me move target power text right -5",
        pre = { "set target power text x offset to 0" },
        status = "applied",
        contains = { "Target Power Text X Offset", "to 5" },
        equals = { "target", "powerOffsetX", 5 },
    },
    {
        input = "help me move boss 3 power text down 5",
        pre = { "set boss power text y offset to 0" },
        status = "applied",
        contains = { "Boss Power Text Y Offset", "to -5" },
        equals = { "boss", "powerOffsetY", -5 },
    },
    {
        input = "left and up 5",
        pre = {
            "set player buff x offset to 0",
            "set player buff y offset to 0",
            "move player buffs",
        },
        status = "applied",
        contains = { "Player Buff X Offset", "Player Buff Y Offset" },
        equals = { "auras3", "shared", "buffGroupOffsetX", -5 },
        equalsAlso = { "auras3", "shared", "buffGroupOffsetY", 5 },
    },
    {
        input = "is it possible to change target width to 300",
        status = "info",
        contains = { "MSUF has a matching control", "Target Width", "kept it unchanged" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "width" },
    },
    {
        input = "where is target max name length",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "where is target name max length",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "where can I change target max name length",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "which setting controls target max name length",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "what controls target name max length",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "can you help me find target max name length",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "show me where target max name length is",
        status = "info",
        contains = { "Target Name Max Length setting location", "number control", "Open Target" },
        notContains = { "Target Name Text setting location", "exact-control navigation bridge is not available", "Done. I changed" },
        unchanged = { "target", "nameMaxChars" },
    },
    {
        input = "which setting controls target power text",
        status = "info",
        contains = { "Target Power Text setting location", "Unit frame text help", "visibility, slot, format, font size, anchor, and offset" },
        notContains = { "I found these MSUF matches", "Done. I changed" },
        unchanged = { "target", "showPowerText" },
    },
    {
        input = "what controls target buffs",
        status = "info",
        contains = { "Target Buffs setting location", "Aura Buffs help", "Aura Buffs" },
        notContains = { "I found these MSUF matches", "Done. I changed" },
    },
    {
        input = "can you help me find target portrait",
        status = "info",
        contains = { "Target Portrait setting location", "Target portrait options", "Portrait Position/Side" },
        notContains = { "I found these MSUF matches", "Done. I changed" },
    },
    {
        input = "show me where target font size is",
        status = "info",
        contains = { "Target Font Size setting location", "Target Name Font Size", "Target HP Font Size", "Target Power Font Size" },
        notContains = { "I found a few possible MSUF controls", "Done. I changed" },
    },
    {
        input = "please don't hide target power text",
        status = "info",
        contains = { "kept MSUF unchanged", "did not hide target power text" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showPowerText" },
    },
    {
        input = "please don't turn off target power text",
        status = "info",
        contains = { "kept MSUF unchanged", "did not turn off target power text" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "showPowerText" },
    },
    {
        input = "please don't change target width to 300",
        status = "info",
        contains = { "kept MSUF unchanged", "did not change target width to 300" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "width" },
    },
    {
        input = "please don't move target power text left 5",
        status = "info",
        contains = { "kept MSUF unchanged", "did not move target power text left 5" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "powerOffsetX" },
    },
    {
        input = "move target power text right -5",
        pre = { "set target power text x offset to 0" },
        status = "applied",
        contains = { "Target Power Text X Offset", "to 5" },
        equals = { "target", "powerOffsetX", 5 },
    },
    {
        input = "lower target power text by 5",
        pre = { "set target power text y offset to 0" },
        status = "applied",
        contains = { "Target Power Text Y Offset", "to -5" },
        notContains = { "Target Power Font Size" },
        equals = { "target", "powerOffsetY", -5 },
    },
    {
        input = "raise target power text by 5",
        pre = { "set target power text y offset to 0" },
        status = "applied",
        contains = { "Target Power Text Y Offset", "to 5" },
        notContains = { "Target Power Font Size" },
        equals = { "target", "powerOffsetY", 5 },
    },
    {
        input = "move boss castbar down 5",
        pre = { "set Boss Castbar Y to 0" },
        status = "applied",
        contains = { "Boss Castbar Y", "to -5" },
        notContains = { "Boss Castbar Height", "Which page and option" },
        equals = { "general", "bossCastbarOffsetY", -5 },
    },
    {
        input = "move boss castbar icon down 5",
        pre = { "set Boss Castbar Icon Y Offset to 0", "set Boss Castbar Y to 0" },
        status = "applied",
        contains = { "Boss Castbar Icon Y Offset", "to -5" },
        notContains = { "Boss Castbar Y from", "Which page and option" },
        equals = { "general", "bossCastIconOffsetY", -5 },
    },
    {
        input = "please move player castbar icon right 4",
        pre = { "set Player Castbar Icon X Offset to 0", "set Player Castbar X to 0" },
        status = "applied",
        contains = { "Player Castbar Icon X Offset", "to 4" },
        notContains = { "Player Castbar X from", "Which page and option" },
        equals = { "general", "castbarPlayerIconOffsetX", 4 },
    },
    {
        input = "could you move target castbar spell text up 7",
        pre = { "set Target Castbar Spell Text Y Offset to 0", "set Target Castbar Y to 0" },
        status = "applied",
        contains = { "Target Castbar Spell Text Y Offset", "to 7" },
        notContains = { "Target Castbar Y from", "Which page and option" },
        equals = { "general", "castbarTargetTextOffsetY", 7 },
    },
    {
        input = "nudge focus castbar time text 6 pixels to the left",
        pre = { "set Focus Castbar Time Text X Offset to 0", "set Focus Castbar X to 0" },
        status = "applied",
        contains = { "Focus Castbar Time Text X Offset", "to -6" },
        notContains = { "Focus Castbar X from", "Which page and option" },
        equals = { "general", "castbarFocusTimeOffsetX", -6 },
    },
    {
        input = "move target castbar icon down and right 3",
        pre = {
            "set Target Castbar Icon X Offset to 0",
            "set Target Castbar Icon Y Offset to 0",
            "set Target Castbar X to 0",
            "set Target Castbar Y to 0",
        },
        status = "applied",
        contains = { "Target Castbar Icon X Offset", "to 3", "Target Castbar Icon Y Offset", "to -3" },
        notContains = { "Target Castbar X from", "Target Castbar Y from", "Which page and option" },
        equals = { "general", "castbarTargetIconOffsetX", 3 },
        equalsAlso = { "general", "castbarTargetIconOffsetY", -3 },
    },
    {
        input = "put target castbar icon on the right",
        pre = { "set Target Castbar Icon Position to LEFT", "set Target Castbar Icon X Offset to 0" },
        status = "applied",
        contains = { "Target Castbar Icon Position", "from left to right" },
        notContains = { "already enabled", "Target Castbar Icon X Offset", "Target Castbar X" },
        equals = { "general", "castbarTargetIconPosition", "RIGHT" },
    },
    {
        input = "move target power text by 5 to the left",
        pre = { "set target power text x offset to 0" },
        status = "applied",
        contains = { "Target Power Text X Offset", "to -5" },
        equals = { "target", "powerOffsetX", -5 },
    },
    {
        input = "move target power text 5 pixels to the left",
        pre = { "set target power text x offset to 0" },
        status = "applied",
        contains = { "Target Power Text X Offset", "to -5" },
        equals = { "target", "powerOffsetX", -5 },
    },
    {
        input = "move boss 3 power text down 5",
        pre = { "set boss power text y offset to 0" },
        status = "applied",
        contains = { "Boss Power Text Y Offset", "to -5" },
        equals = { "boss", "powerOffsetY", -5 },
    },
    {
        input = "move target power text down and right 5",
        pre = {
            "set target power text x offset to 0",
            "set target power text y offset to 0",
        },
        status = "applied",
        contains = { "Target Power Text X Offset", "Target Power Text Y Offset" },
        equals = { "target", "powerOffsetX", 5 },
        equalsAlso = { "target", "powerOffsetY", -5 },
    },
    {
        input = "position target name text top left",
        status = "ambiguous",
        contains = { "does not have that fixed anchor choice", "Target Name X Offset", "Target Name Y Offset", "kept it unchanged" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "nameTextAnchor" },
    },
    {
        input = "position target name text center",
        status = "applied",
        contains = { "Target Name Text Anchor", "center" },
        equals = { "target", "nameTextAnchor", "CENTER" },
    },
    {
        input = "move it 5 pixels to the left",
        pre = {
            "set target power text x offset to 0",
            "can you help me move target power text",
        },
        status = "applied",
        contains = { "Target Power Text X Offset", "to -5" },
        equals = { "target", "powerOffsetX", -5 },
    },
    {
        input = "nudge it to the left by 5",
        pre = {
            "set target power text x offset to 0",
            "can you help me move target power text",
        },
        status = "applied",
        contains = { "Target Power Text X Offset", "to -5" },
        equals = { "target", "powerOffsetX", -5 },
    },
    {
        input = "a little more left",
        pre = {
            "set target power text x offset to 0",
            "can you help me move target power text",
        },
        status = "applied",
        contains = { "Target Power Text X Offset", "to -10" },
        equals = { "target", "powerOffsetX", -10 },
    },
    {
        input = "default",
        pre = {
            "set player leader icon role icon style to classic",
            "change player leader icon role icon style",
        },
        status = "applied",
        contains = { "Player Leader Icon Role Icon Style", "Default" },
        equals = { "player", "leaderIconStyle", "BLIZZARD" },
    },
    {
        input = "left 5",
        pre = { "move party readycheck" },
        status = "applied",
        contains = { "Party Ready Check Icon X Offset" },
        notContains = { "Bar Gradient Direction" },
    },
    {
        input = "the first one",
        pre = { "move player buffs" },
        status = "ambiguous",
        contains = { "how should player buff grow", "Player Buff Growth" },
        notContains = { "which way should I move player buff" },
    },
    {
        input = "number 1",
        pre = { "move player buffs" },
        status = "ambiguous",
        contains = { "how should player buff grow", "Player Buff Growth" },
        notContains = { "which way should I move player buff" },
    },
    {
        input = "position target power text top left",
        status = "ambiguous",
        contains = { "does not have that fixed anchor choice", "Target Power Text X Offset", "Target Power Text Y Offset", "kept it unchanged" },
        notContains = { "Target Buff Duration Bar Position", "Done. I changed" },
        unchanged = { "target", "powerOffsetX" },
    },
    {
        input = "move target name text down 5",
        pre = {
            "set target power text y offset to 0",
            "set target name text y offset to 0",
            "can you help me move target power text",
        },
        status = "applied",
        contains = { "Target Name Y Offset" },
        notContains = { "Target Power Text Y Offset" },
        preserves = { "target", "powerOffsetY" },
        equals = { "target", "nameOffsetY", -5 },
    },
    {
        input = "where can I move target power bar?",
        status = "applied",
        contains = { "Target Power Bar Position setting location", "Power Bar help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I detach target power bar?",
        status = "applied",
        contains = { "Target Detach Power Bar from Frame setting location", "Power Bar help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "detach target power bar",
        status = "applied",
        contains = { "Target Detach Power Bar from Frame" },
    },
    {
        input = "where can I turn off class resources?",
        status = "applied",
        contains = { "Class Resource setting location", "Opened Class Resources", "Class Resources help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I turn off Class Resource?",
        status = "applied",
        contains = { "Class Resource setting location", "Class Resources help", "ask for an exact change" },
        notContains = { "Done. I changed", "Done. Opened" },
    },
    {
        input = "can I hide combo points?",
        status = "applied",
        contains = { "Combo Points Visibility setting location", "Class Resources help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "hide class resources",
        status = "applied",
        contains = { "Class Resource" },
    },
    {
        input = "where can I move combo points?",
        status = "applied",
        contains = { "Combo Points Position setting location", "Class Resources help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I make class resources wider?",
        status = "applied",
        contains = { "Class Resource Width setting location", "Class Resources help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I turn off Boss Name No Ellipsis?",
        status = "applied",
        contains = { "Boss Name No Ellipsis setting location", "Boss Frames", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "Done. Opened" },
    },
    {
        input = "should I turn off Boss Buff Show Cooldown Swipe?",
        status = "info",
        contains = { "Boss Buff Show Cooldown Swipe decision help", "Boss Frames", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "Done. Opened" },
    },
    {
        input = "why is Boss Buff Show Cooldown Swipe missing?",
        status = "info",
        contains = { "Boss Buff Show Cooldown Swipe troubleshooting help", "Boss Frames", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "Done. Opened" },
    },
    {
        input = "why is Boss Debuff Dispellable Filter missing?",
        status = "info",
        contains = { "Boss Debuff Dispellable Filter troubleshooting help", "Boss Frames", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "Done. Opened" },
    },
    {
        input = "why cant I see Global WoW UI Scale Override?",
        status = "info",
        contains = { "Global WoW UI Scale Override troubleshooting help", "Dashboard", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "Done. Opened" },
    },
    {
        input = "do I need Add Color to Empowered Stages?",
        status = "info",
        contains = { "Add Color to Empowered Stages decision help", "Cast Bars", "I did not change it" },
        notContains = { "Which page and option", "Done. I changed", "Done. Opened" },
    },
    {
        input = "is it safe to turn off Boss Cast Bar?",
        status = "info",
        contains = { "Boss Cast Bar decision help", "safer first step", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "Done. Opened" },
    },
    {
        input = "where can I turn off combat timer?",
        status = "applied",
        contains = { "Combat Timer setting location", "Gameplay help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I hide combat timer?",
        status = "applied",
        contains = { "Combat Timer setting location", "Gameplay help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "hide combat timer",
        status = "applied",
        contains = { "Combat Timer" },
    },
    {
        input = "where can I move combat crosshair?",
        status = "applied",
        contains = { "Combat Crosshair Position setting location", "Gameplay help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I make combat crosshair bigger?",
        status = "applied",
        contains = { "Combat Crosshair Size setting location", "Gameplay help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "where can I hide totem frame?",
        status = "applied",
        contains = { "Totem Frame setting location", "Gameplay help" },
        notContains = { "Done. I changed" },
    },
    {
        input = "move combat timer down 8",
        status = "applied",
        contains = { "Combat Timer Offset Y" },
    },
    {
        input = "set crosshair size to 60",
        status = "applied",
        contains = { "Combat Crosshair Size" },
    },
    {
        input = "where can I import a profile?",
        status = "info",
        contains = { "Profile import help", "Open Profiles" },
        notContains = { "Done. Add your MSUF profile string below.", "I can apply" },
    },
    {
        input = "can I import a profile string?",
        status = "info",
        contains = { "Profile import help", "Profile import needs a full MSUF profile string" },
        notContains = { "Done. Add your MSUF profile string below.", "I can apply" },
    },
    {
        input = "import profile string",
        status = "navigated",
        contains = { "Done. Add your MSUF profile string below." },
    },
    {
        input = "where can I reset my profile?",
        status = "info",
        contains = { "Profile reset help", "Reset Active Profile lives in Profiles" },
        notContains = { "I can apply Reset active profile", "Done. I changed" },
    },
    {
        input = "can I reset my profile?",
        status = "info",
        contains = { "Profile reset help", "confirmation-gated" },
        notContains = { "I can apply Reset active profile", "Done. I changed" },
    },
    {
        input = "reset active profile",
        status = "confirmation_needed",
        contains = { "I can apply Reset active profile" },
    },
    {
        input = "where is factory reset?",
        status = "info",
        contains = { "Factory reset help", "Display & Recovery" },
        notContains = { "I can apply Factory reset all MSUF options", "Done. I changed" },
    },
    {
        input = "can I factory reset?",
        status = "info",
        contains = { "Factory reset help", "confirmation-gated" },
        notContains = { "I can apply Factory reset all MSUF options", "Done. I changed" },
    },
    {
        input = "factory reset all",
        status = "confirmation_needed",
        contains = { "I can apply Factory reset all MSUF options" },
    },
    {
        input = "where can I delete a profile?",
        status = "info",
        contains = { "Profile delete help", "exact profile name plus confirmation" },
        notContains = { "I can apply Delete profile", "Done. I changed" },
    },
    {
        input = "can I delete a profile?",
        status = "info",
        contains = { "Profile delete help", "I do not guess which profile to delete" },
        notContains = { "I can apply Delete profile", "Done. I changed" },
    },
    {
        input = "delete profile Raid",
        status = "confirmation_needed",
        contains = { "I can apply Delete profile raid" },
    },
    {
        input = "can I undo this later?",
        status = "info",
        contains = { "Safety guidance", "Normal Assistant setting changes can be undone" },
        notContains = { "Done. Reverted", "Done. Reapplied" },
    },
    {
        input = "can you fix target buffs?",
        status = "applied",
        contains = { "Target aura check", "Suggested fixes" },
        notContains = { "Which listed option do you want me to use?" },
    },
    {
        pre = { "why are target buffs hidden?" },
        input = "run checks",
        status = "applied",
        contains = { "MSUF Assistant details" },
        notContains = { "Which listed option do you want me to use?" },
    },
    {
        input = "where can I change target health bar color?",
        status = "applied",
        contains = { "Target Health Color Scheme setting location", "Target frame page" },
        notContains = { "Done. I changed", "Which page and option" },
    },
    {
        input = "can I make player health class colored?",
        status = "applied",
        contains = { "Player Health Color Scheme setting location", "class-colored" },
        notContains = { "Done. I changed", "Which page and option" },
    },
    {
        input = "can I change the bar texture?",
        status = "applied",
        contains = { "Global Bar Texture setting location", "Bars" },
        notContains = { "I don't see a matching texture", "Done. I changed" },
    },
    {
        input = "where can I make player frame transparent?",
        status = "applied",
        contains = { "Player Opacity setting location", "Player HP Bar Opacity", "Player Background Opacity" },
        notContains = { "Done. I changed" },
        unchanged = { "player", "hpBarAlpha" },
    },
    {
        input = "can I reduce target opacity?",
        status = "applied",
        contains = { "Target Opacity setting location", "Target HP Bar Opacity", "Target Background Opacity" },
        notContains = { "Done. I changed" },
        unchanged = { "target", "hpBarAlpha" },
    },
    {
        input = "where can I set range fade for raid frames?",
        status = "applied",
        contains = { "Raid Range Fade setting location", "Group Health & Text", "Range Fade Alpha" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I make raid frames less faded out?",
        status = "applied",
        contains = { "Raid Range Fade setting location", "Range Fade Alpha" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I turn off absorb overlay?",
        status = "applied",
        contains = { "Absorb Display Mode setting location", "Bars" },
        notContains = { "Which page and option", "Done. I changed" },
    },
    {
        input = "where can I turn off heal prediction?",
        status = "applied",
        contains = { "Heal Prediction Overlay setting location", "Bars" },
        notContains = { "Done. I changed" },
    },
    {
        input = "where can I turn off aggro border?",
        status = "applied",
        contains = { "Aggro Border setting location", "Highlight Borders" },
        notContains = { "Done. I changed" },
    },
    {
        input = "can I make target health text white?",
        status = "applied",
        contains = { "Target Text Color setting location", "Global Font Color" },
        notContains = { "Target Health Text setting location", "Done. I changed" },
    },
    {
        input = "where can I set player frame background color?",
        status = "applied",
        contains = { "Player background color help", "Player Background Opacity" },
        notContains = { "Done. I changed" },
    },
    {
        input = "make target border red",
        status = "info",
        contains = { "Target border color help", "does not expose a simple per-Target frame border color setting" },
        notContains = { "Which page and option", "Done. I changed" },
    },
    {
        input = "where can I move target frame?",
        status = "applied",
        contains = { "Target Position setting location", "Target X Position", "Target Y Position", "Custom Anchor Frame" },
        notContains = { "Done. I changed", "Unit Frames help" },
        unchanged = { "target", "offsetX" },
    },
    {
        input = "can I move my player frame?",
        status = "applied",
        contains = { "Player Position setting location", "Player X Position", "Player Y Position", "MSUF Edit Mode" },
        notContains = { "I could not match that", "Done. I changed" },
        unchanged = { "player", "offsetX" },
    },
    {
        input = "where can I set target frame x offset?",
        status = "applied",
        contains = { "Target Position setting location", "Target X Position" },
        notContains = { "Done. I changed", "Unit Frames help" },
        unchanged = { "target", "offsetX" },
    },
    {
        input = "can I anchor target frame to player?",
        status = "applied",
        contains = { "Target Anchor setting location", "Target Anchor to", "Target Custom Anchor Frame" },
        notContains = { "Done. I changed", "Player Anchor setting location" },
        unchanged = { "target", "anchorToUnitframe" },
    },
    {
        input = "why can't I drag player frame?",
        status = "info",
        contains = { "Player frame movement help", "MSUF Edit Mode", "combat lockdown" },
        notContains = { "Done. I changed", "Player frame enabled" },
        unchanged = { "player", "offsetX" },
    },
    {
        input = "where can I reset player frame position?",
        status = "applied",
        contains = { "Player Position setting location", "reset-position action", "I do not reset it from a location question" },
        notContains = { "Open MSUF first so I can restore factory defaults", "Done. I changed" },
        unchanged = { "player", "offsetX" },
    },
    {
        input = "where can I lock frames?",
        status = "info",
        contains = { "Frame movement / lock help", "no single universal lock-all-unit-frames toggle", "Gameplay" },
        notContains = { "Search results", "Blizzard Unit Frames", "Done. I changed" },
    },
    {
        input = "can I move frames in combat?",
        status = "info",
        contains = { "Combat lockdown help", "WoW blocks protected UI changes", "MSUF Edit Mode" },
        notContains = { "MSUF Edit Mode controls are not available from here", "Done. I changed" },
    },
    {
        input = "why can I not move frames in combat?",
        status = "info",
        contains = { "Combat lockdown help", "Leave combat", "exact X/Y and anchor commands" },
        notContains = { "MSUF Edit Mode controls are not available from here", "Done. I changed" },
    },
    {
        input = "can I unlock combat timer to drag it?",
        status = "applied",
        contains = { "Combat Timer setting location", "Gameplay help", "lock" },
        notContains = { "Combat lockdown help", "Done. I changed" },
    },
    {
        input = "where can I move raid marker icon?",
        status = "applied",
        contains = { "Raid Marker position setting location", "Group Status & Indicators", "Raid Marker X Offset", "Raid Marker Y Offset" },
        notContains = { "Indicator position help", "Unit Frames help", "Done. I changed" },
    },
    {
        input = "move target frame right 10",
        status = "applied",
        contains = { "Target X Position" },
    },
    {
        input = "move raid marker icon up 4",
        status = "applied",
        contains = { "Raid Raid Marker Y Offset" },
    },
    {
        input = "what setting controls target font size?",
        status = "applied",
        contains = { "Target Font Size setting location", "Target Name Font Size", "Target HP Font Size", "Target Power Font Size" },
        notContains = { "Target Size setting location", "Done. I changed" },
    },
    {
        input = "which page has player portrait style?",
        status = "applied",
        contains = { "Player Portrait setting location", "Portrait Style", "Player frame page" },
        notContains = { "Done. I changed", "Portrait help" },
    },
    {
        input = "what controls party ready check size?",
        status = "applied",
        contains = { "Ready Check size setting location", "Party frames", "Group Status & Indicators" },
        notContains = { "Ready Check help", "Done. I changed" },
    },
    {
        input = "where do I change raid frame spacing?",
        status = "applied",
        contains = { "Raid Spacing setting location", "Group Layout", "gap between frames" },
        notContains = { "Group frame layout help", "Done. I changed" },
    },
    {
        input = "what setting controls target aura cooldown text size?",
        status = "applied",
        contains = { "Target Aura Cooldown Text setting location", "Aura Style", "cooldown/stack text" },
        notContains = { "Aura Style help", "Done. I changed" },
    },
    {
        input = "where can I blacklist a spell from target buffs?",
        status = "applied",
        contains = { "Target Buff Filter setting location", "Aura Filters", "Aura Editing Scope", "Aura Filter Lane" },
        notContains = { "Target Buffs setting location", "Done. I changed" },
    },
    {
        input = "which setting controls uninterruptible cast color?",
        status = "applied",
        contains = { "Non-Interruptible Cast Color setting location", "global cast-bar color option", "Interrupt Ready indicator" },
        notContains = { "What value do you want me to use", "Done. I changed" },
    },
    {
        input = "where do I make focus kick tracker bigger?",
        status = "applied",
        contains = { "Focus Kick Width setting location", "Cast Bars", "Focus Kick Tracker controls" },
        notContains = { "Focus Size setting location", "Done. I changed" },
    },
    {
        input = "what setting detaches player power bar?",
        status = "applied",
        contains = { "Player Detach Power Bar from Frame setting location", "Player page" },
        notContains = { "Detached Power Bar Background Texture", "Done. I changed" },
        unchanged = { "player", "powerBarDetached" },
    },
    {
        input = "what controls target of target frame width?",
        status = "applied",
        contains = { "Target of Target Width setting location", "Target of Target frame page" },
        notContains = { "MSUF Assistant", "Done. I changed" },
    },
    {
        input = "what setting controls mythic raid name text size?",
        status = "applied",
        contains = { "Mythic Raid Name Font Size setting location", "Group Health & Text" },
        notContains = { "Group frame layout help", "Done. I changed" },
    },
    {
        input = "where do I change player class color mode?",
        status = "applied",
        contains = { "Class Resources Player HP Color Mode setting location", "Class Resources" },
        notContains = { "Done. I changed" },
    },
    {
        input = "which setting controls target portrait border color?",
        status = "applied",
        contains = { "Target Portrait Border color setting location", "Custom color", "Colors > Portrait Colors" },
        notContains = { "Focus Target Portrait Border", "Done. I changed" },
    },
    {
        input = "what setting controls boss castbar spell name font size?",
        status = "applied",
        contains = { "Boss Castbar Spell Name Font Size setting location", "Boss Frames", "set Boss Castbar Spell Name Font Size to 14" },
        notContains = { "Boss Name Text", "Done. I changed" },
    },
    {
        input = "where can I change party dead background color?",
        status = "applied",
        contains = { "Party Dead Background Color setting location", "Group Health & Text", "I did not change it from this location question" },
        notContains = { "Done. I changed" },
    },
    {
        input = "how do I adjust party dead background color?",
        status = "applied",
        contains = { "Party Dead Background Color setting location", "Group Health & Text" },
        notContains = { "Done. I changed" },
    },
    {
        input = "which option controls raid group border padding?",
        status = "applied",
        contains = { "Raid Group Border Padding setting location", "Group Health & Text" },
        notContains = { "Mythic Raid Group Border Padding", "Done. I changed" },
    },
    {
        input = "where do I set aura blacklist preset?",
        status = "applied",
        contains = { "Hidden Aura Preset setting location", "Aura Style", "a choice control" },
        notContains = { "Done. I changed" },
    },
    {
        input = "which setting controls detached power bar outline?",
        status = "applied",
        contains = { "Detached Power Bar Outline setting location", "Class Resources" },
        notContains = { "Detached Power Bar Background Texture", "Done. I changed" },
    },
    {
        input = "what does target portrait border do?",
        status = "applied",
        contains = { "Target Portrait Border explanation", "Target", "Current value", "Related nearby settings" },
        notContains = { "I found these MSUF matches", "Focus Target Portrait Border", "Done. I changed" },
    },
    {
        input = "what is raid group border padding for?",
        status = "applied",
        contains = { "Raid Group Border Padding explanation", "Group Health & Text", "spacing around the group border" },
        notContains = { "Raid Dispel Overlay Detects", "I found these MSUF matches", "Done. I changed" },
    },
    {
        input = "why would I use party dead background color?",
        status = "applied",
        contains = { "Party Dead Background Color explanation", "dead group members", "Group Health & Text" },
        notContains = { "Suggested fixes", "Show Party group frames", "Done. I changed" },
    },
    {
        input = "what does hidden aura preset do?",
        status = "applied",
        contains = { "Hidden Aura Preset explanation", "Aura Style", "hidden/blacklisted aura" },
        notContains = { "Target aura check", "Suggested fixes", "Done. I changed" },
    },
    {
        input = "explain detached power bar outline",
        status = "applied",
        contains = { "Detached Power Bar Outline explanation", "Controls only the detached Player power outline", "Class Resources" },
        notContains = { "Font rendering help", "Done. I changed" },
    },
    {
        input = "what does boss castbar spell name font size control?",
        status = "applied",
        contains = { "Boss Castbar Spell Name Font Size explanation", "Boss Frames", "set Boss Castbar Spell Name Font Size to 14" },
        notContains = { "Font rendering help", "Boss Name Text", "Done. I changed" },
    },
    {
        input = "explain raid range fade alpha",
        status = "applied",
        contains = { "Raid Range Fade Alpha explanation", "out-of-range frames", "set Raid Range Fade Alpha to 40" },
        notContains = { "Alpha and opacity help", "Done. I changed" },
    },
    {
        input = "where can I change Menu Edge Snap?",
        status = "applied",
        contains = { "Menu Edge Snap setting location", "Miscellaneous", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "MSUF Menu Scale" },
    },
    {
        input = "where is menu edge snap?",
        status = "applied",
        contains = { "Menu Edge Snap setting location", "Miscellaneous", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "MSUF Menu Scale" },
    },
    {
        input = "what does Menu Edge Snap do?",
        status = "applied",
        contains = { "Menu Edge Snap explanation", "Miscellaneous", "I did not change it" },
        notContains = { "Already set", "Done. I changed", "MSUF Menu Scale explanation" },
    },
    {
        input = "cap player auaras at 2",
        status = "applied",
        contains = { "Player Buff Max Icons", "Player Debuff Max Icons" },
        notContains = { "MSUF Menu Scale", "Which page and option" },
    },
    {
        input = "can yu move my player frame?",
        status = "info",
        contains = { "Player frame movement help", "exact direction/amount" },
        notContains = { "Which page and option" },
    },
    {
        input = "make player hp txt bigger",
        status = "applied",
        contains = { "Player HP Font Size" },
        notContains = { "frame width", "frame height" },
    },
    {
        input = "make target buff cooldown txt bigger",
        status = "applied",
        contains = { "Target Buff Cooldown Text Size" },
        notContains = { "Target Buff Icon Size" },
    },
    {
        input = "make target combat status icn smaller",
        status = "applied",
        contains = { "Target Combat Indicator Size" },
        notContains = { "Which frame do you want me to resize" },
    },
    {
        input = "make target pwr txt bigger",
        status = "applied",
        contains = { "Target Power Font Size" },
        notContains = { "Target X Position", "Which page and option" },
    },
    {
        input = "move party readycheck up",
        status = "applied",
        contains = { "Party Ready Check Icon Y Offset" },
        notContains = { "Party Y Position", "Which page and option" },
    },
    {
        input = "hide player raidmark",
        status = "applied",
        contains = { "Player Raid Marker" },
        notContains = { "Which page and option" },
    },
    {
        input = "make target aura cd txt bigger",
        status = "applied",
        contains = { "Target Cooldown Text Size" },
        notContains = { "Target Buff Icon Size", "Which page and option" },
    },
    {
        input = "make raid debuf cd text bigger",
        status = "applied",
        contains = { "Raid Debuff Cooldown Font Size" },
        notContains = { "I don't see an MSUF aura option", "Global Font Size" },
    },
    {
        input = "now anchor group frame buffs to the left",
        pre = { "move group frame names down" },
        status = "applied",
        contains = { "Party Buff Anchor", "Raid Buff Anchor", "Mythic Raid Buff Anchor", "bottomleft" },
        notContains = { "Which page and option", "I found multiple matches" },
    },
    {
        input = "set raid cooldown text size to 18",
        status = "ambiguous",
        contains = { "Raid aura Cooldown Text needs a lane", "Buff and Debuff" },
        notContains = { "Global Font Size", "Done. I changed" },
    },
    {
        input = "can you rotate player frame in 3D",
        status = "info",
        contains = { "does not have a 3D frame-rotation control", "kept everything unchanged", "Closest MSUF options" },
        notContains = { "Yes", "I found these MSUF matches" },
    },
    {
        input = "can you add a weather radar",
        status = "info",
        contains = { "does not provide weather data or a radar widget", "kept everything unchanged" },
        notContains = { "Yes", "likely match" },
    },
    {
        input = "can you play chess",
        status = "info",
        contains = { "cannot play chess", "kept everything unchanged" },
        notContains = { "Yes", "I found these MSUF matches" },
    },
    {
        input = "is it possible to rotate player frame in 3D",
        status = "info",
        contains = { "does not have a 3D frame-rotation control", "kept everything unchanged" },
        notContains = { "Yes", "MSUF can do that" },
    },
    {
        input = "could i add a weather radar",
        status = "info",
        contains = { "does not provide weather data or a radar widget", "kept everything unchanged" },
        notContains = { "Yes", "sounds like an MSUF setting request" },
    },
}

for _, case in ipairs(cases) do
    clearAssistantState()
    if type(case.pre) == "table" then
        for _, preInput in ipairs(case.pre) do
            A.Submit(preInput)
        end
    end
    local before
    if case.unchanged then before = dbValue(case.unchanged) end
    local preservedBefore
    if case.preserves then preservedBefore = dbValue(case.preserves) end

    local result = A.Submit(case.input)
    assert(type(result) == "table", case.input .. ": missing result")
    local status = result.status or result.result
    local expectedStatus = expectedSemanticStatus(case)
    assert(status == expectedStatus
        or (expectedStatus == "applied" and status == "unchanged")
        or (expectedStatus == "info" and status == "navigated"),
        case.input .. ": expected " .. tostring(expectedStatus) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(case.input, result.text or "")
    assertContains(case.input, result.text or "", case.contains)
    assertNotContains(case.input, result.text or "", case.notContains)

    if case.unchanged then
        local after = dbValue(case.unchanged)
        assert(after == before, case.input .. ": location question changed DB value from " .. tostring(before) .. " to " .. tostring(after))
    end
    if case.preserves then
        local after = dbValue(case.preserves)
        assert(after == preservedBefore, case.input .. ": changed the previous conversation subject from " .. tostring(preservedBefore) .. " to " .. tostring(after))
    end
    if case.equals then
        local path = { case.equals[1], case.equals[2] }
        for i = 3, #case.equals - 1 do path[#path + 1] = case.equals[i] end
        local after = dbValue(path)
        local expected = case.equals[#case.equals]
        assert(after == expected, case.input .. ": expected DB value " .. tostring(expected) .. ", got " .. tostring(after))
    end
    if case.equalsAlso then
        local path = {}
        for i = 1, #case.equalsAlso - 1 do path[#path + 1] = case.equalsAlso[i] end
        local after = dbValue(path)
        local expected = case.equalsAlso[#case.equalsAlso]
        assert(after == expected, case.input .. ": expected additional DB value " .. tostring(expected) .. ", got " .. tostring(after))
    end

    checkPanel(case.input)
    clearAssistantState()
end

io.write("assistant_natural_setting_conversation_audit: ok cases=" .. tostring(#cases) .. "\n")
