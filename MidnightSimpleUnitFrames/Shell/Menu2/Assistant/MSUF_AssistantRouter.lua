local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

--- Shell/Menu2/Assistant/MSUF_AssistantRouter.lua
---
--- Conversation router that decides whether an input should be treated as a
--- pending confirmation/choice, contextual assistant command, knowledge/help
--- request, or friendly no-match response. It intentionally runs before the
--- heavy parser fallback so short page-local commands can resolve quickly.
---
--- Keep routing heuristics conservative: mutation-like text should reach the
--- parser, while pure help/conversation can be answered here.

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local COMMAND_TERMS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset", "copy",
    "add", "put", "clear", "increase", "decrease", "raise", "lower", "bump", "grow", "shrink", "detach", "attach", "anchor", "follow", "undock", "dock", "embed",
    "export", "import", "create", "delete", "remove", "switch", "assign", "rename", "open", "close", "toggle",
    "diagnose", "why", "help", "undo", "redo", "yes", "cancel", "next", "back", "finish", "start", "stop", "enter", "leave",
    "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken",
    "einblenden", "ausblenden", "verschiebe", "verschieben", "setze", "stelle", "erhoehe", "erhoehen", "senke", "reduziere",
    "abkoppeln", "ankoppeln", "einbetten", "oeffne", "suche", "finde",
}
local COLOR_TERMS = {
    "red", "green", "blue", "yellow", "white", "black", "orange", "purple", "pink", "gold", "gray", "grey",
    "rot", "gruen", "blau", "gelb", "weiss", "schwarz", "lila", "grau",
}
local FLOW_TERMS = {
    "yes", "y", "ja", "confirm", "apply", "cancel", "no", "nein", "abort", "stop", "next", "back", "finish", "undo", "redo",
}
local DISCORD_INVITE = "https://discord.gg/2Gf9b2Wprz"
local CURSEFORGE_PAGE = "https://www.curseforge.com/wow/addons/midnightsimpleunitframes"
local WOWHEAD_GUIDES = "https://www.wowhead.com/guides"

local WOW_JOKES_EN = {
    "Sure. Why did the unit frame join the raid? It wanted a stable group.",
    "Sure. My castbar tried to tell a joke, but someone interrupted it before the punchline.",
    "Sure. The healer asked for cleaner frames, so MSUF dispelled three pixels of chaos.",
    "Sure. I rolled need on a perfect UI. The loot window said: already equipped.",
    "Sure. Why did the DPS resize the target frame? To make the meters look smaller.",
    "Sure. MSUF went to a raid meeting and came back with one assignment: keep everyone visible.",
    "Sure. The power bar wanted more space, but the health bar said: not in this layout.",
    "Sure. I asked the boss frame for feedback. It said: too many targets, not enough focus.",
    "Sure. My favorite pull timer is a checkbox. It wipes less often than most countdowns.",
    "Sure. Why did the unit frame stay out of fire? It had range fade enabled.",
    "Sure. Target of Target text tried dating raid markers. It said the relationship was complicated.",
    "Sure. The profile import promised it was simple, then arrived with seven backups and a reload prompt.",
}

local WOW_JOKES_DE = {
    "Klar. Warum ist der Unit Frame dem Raid beigetreten? Er wollte endlich eine stabile Gruppe.",
    "Klar. Meine Castbar wollte einen Witz erzaehlen, aber jemand hat sie vor der Pointe unterbrochen.",
    "Klar. Der Heiler wollte mehr Uebersicht, also hat MSUF drei Pixel Chaos dispellt.",
    "Klar. Ich habe Bedarf auf ein perfektes UI gewuerfelt. Das Lootfenster sagte: schon angelegt.",
    "Klar. Warum hat der DPS das Target Frame groesser gemacht? Damit die Meter kleiner wirken.",
    "Klar. MSUF kam aus dem Raidmeeting mit genau einer Aufgabe zurueck: alle sichtbar halten.",
    "Klar. Die Power Bar wollte mehr Platz, aber die Health Bar sagte: nicht in diesem Layout.",
    "Klar. Ich habe das Boss Frame nach Feedback gefragt. Es sagte: zu viele Ziele, zu wenig Fokus.",
    "Klar. Mein liebster Pulltimer ist eine Checkbox. Die wiped seltener als die meisten Countdowns.",
    "Klar. Warum bleibt der Unit Frame aus dem Feuer? Range Fade ist an.",
    "Klar. Target-of-Target Text war mit Raidmarkern aus. Es sagte: es ist kompliziert.",
    "Klar. Der Profilimport versprach, einfach zu sein, und kam dann mit sieben Backups und einem Reload-Hinweis.",
}

local MUTATION_TERMS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset",
    "copy", "export", "import", "create", "delete", "remove", "add", "put", "clear", "switch", "assign", "rename", "close", "toggle",
    "increase", "decrease", "raise", "lower", "bump", "grow", "shrink", "detach", "attach", "anchor", "follow", "undock", "dock", "embed",
    "start", "stop", "enter", "leave", "select", "use", "apply",
    "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken",
    "einblenden", "ausblenden", "verschiebe", "verschieben", "setze", "stelle", "erhoehe", "erhoehen", "senke", "reduziere",
    "abkoppeln", "ankoppeln", "einbetten",
}
local NAV_HELP_TERMS = {
    "open", "go to", "where", "where is", "where are", "find", "search", "show me", "help", "why", "diagnose", "what", "how",
    "oeffne", "wo", "wo ist", "finde", "suche", "hilfe", "warum", "wie",
}
local EXPLICIT_DOMAIN_TERMS = {
    "unitframe", "unitframes", "unit frame", "unit frames",
    "player", "target", "focus", "pet", "boss", "targettarget", "target of target", "focustarget", "focus target", "party", "raid", "group", "group frames",
    "spieler", "ziel", "fokus", "begleiter", "gruppe", "gruppenframes",
    "castbar", "cast bar", "auras", "aura", "buff", "debuff", "profile", "profiles", "class resource", "class power", "gameplay",
    "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus",
}

local AURA_OUT_OF_SCOPE_TERMS = {
    "aura", "auras", "auren",
    "group aura", "group auras", "gruppen aura", "gruppenauren",
}
local AURA_BUFF_TERMS = { "buff", "buffs", "debuff", "debuffs" }
local AURA_BUFF_CONTEXT_TERMS = {
    "filter", "filters", "blacklist", "whitelist", "preset", "quick setup", "setup",
    "hidden", "hide", "show", "open", "help", "why", "where", "settings",
    "turn", "turn on", "turn off", "on", "off", "enable", "disable", "enabled", "disabled",
    "set", "change", "make", "size", "count", "max", "icon", "icons", "per row", "growth",
    "copy", "use", "kopieren", "kopiere", "uebernehme", "uebernehmen",
    "own", "mine", "only mine", "only player", "raid filter", "player filter",
    "stack", "cooldown", "pandemic",
}

local PAGE_CONTEXT = {
    uf_player = { prefix = "player", label = "Player" },
    uf_target = { prefix = "target", label = "Target" },
    uf_focus = { prefix = "focus", label = "Focus" },
    uf_pet = { prefix = "pet", label = "Pet" },
    uf_targettarget = { prefix = "targettarget", label = "Target of Target" },
    uf_focustarget = { prefix = "focustarget", label = "Focus Target" },
    uf_boss = { prefix = "boss", label = "Boss Frames" },
    opt_castbar = { prefix = "castbar", label = "Castbars" },
    opt_bars = { prefix = "bar", label = "Bars" },
    opt_colors = { prefix = "color", label = "Colors" },
    opt_fonts = { prefix = "font", label = "Fonts" },
    opt_misc = { prefix = "dashboard", label = "Miscellaneous" },
    classpower = { prefix = "class resource", label = "Class Resources" },
    gameplay = { prefix = "gameplay", label = "Gameplay" },
    profiles = { prefix = "profile", label = "Profiles" },
    gf_layout = { prefix = "group", label = "Group Layout" },
    gf_bars = { prefix = "group text", label = "Group Health & Text" },
    gf_indicators = { prefix = "group indicator", label = "Group Indicators" },
    gf_auras = { prefix = "group aura", label = "Group Auras" },
    auras3 = { prefix = "aura style", label = "Aura Style" },
    auras3_buffs = { prefix = "aura buff", label = "Aura Buffs" },
    auras3_debuffs = { prefix = "aura debuff", label = "Aura Debuffs" },
    auras3_styling = { prefix = "aura style", label = "Aura Style" },
    auras3_filters = { prefix = "aura filter", label = "Aura Filters" },
}

local GROUP_CONTEXT_PAGES = {
    gf_layout = true,
    gf_bars = true,
    gf_indicators = true,
}

local GROUP_SCOPE_PREFIXES = {
    party = "party",
    raid = "raid",
    mythicraid = "mythic raid",
    mythic = "mythic raid",
    ["mythic raid"] = "mythic raid",
}

local function Normalize(text)
    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
    return Trim(text)
end

local function MaybeYield()
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
end

local function HasPhrase(text, phrase)
    text = Normalize(text)
    phrase = Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function ContainsAny(text, words)
    text = Normalize(text)
    for i = 1, #(words or {}) do
        if HasPhrase(text, words[i]) then return true end
    end
    return false
end

local exactAssistantKeyCache
local exactAssistantKeyCacheCount = 0

local function LooksLikeExactAssistantKey(text)
    local raw = tostring(text or "")
    if not raw:find("[%.%_]") then return false end
    local registry = A.Registry
    if not registry then return false end
    local settings = type(registry.AllSettings) == "function" and registry:AllSettings() or {}
    local actions = type(registry.AllActions) == "function" and registry:AllActions() or {}
    local count = #settings + #actions
    if type(exactAssistantKeyCache) ~= "table" or exactAssistantKeyCacheCount ~= count then
        exactAssistantKeyCache = {}
        exactAssistantKeyCacheCount = count
        for i = 1, #settings do
            local key = tostring(settings[i] and settings[i].key or ""):lower()
            if key ~= "" then exactAssistantKeyCache[key] = true end
        end
        for i = 1, #actions do
            local key = tostring(actions[i] and actions[i].key or ""):lower()
            if key ~= "" then exactAssistantKeyCache[key] = true end
        end
    end
    for token in raw:gmatch("[%w_%.]+") do
        if token:find("[%.%_]") and exactAssistantKeyCache[token:lower()] then return true end
    end
    return false
end

local function LooksLikeBareLookup(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if norm:match("%d") then return false end
    if norm:match("#%x%x%x") then return false end
    for i = 1, #COMMAND_TERMS do
        if HasPhrase(norm, COMMAND_TERMS[i]) then return false end
    end
    for i = 1, #COLOR_TERMS do
        if HasPhrase(norm, COLOR_TERMS[i]) then return false end
    end
    return true
end


local function LooksLikeMutation(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if ContainsAny(norm, { "help", "why", "where", "where is", "what", "how", "search", "find", "show commands", "hilfe", "warum", "wo", "suche", "finde" }) then
        return false
    end
    return ContainsAny(norm, MUTATION_TERMS)
end

local function LooksLikeKnowledgeQuestionPrefix(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if norm:match("^how%s+do%s+i%s+undo") or norm:match("^how%s+can%s+i%s+undo") then return true end
    if norm:match("^how%s+do%s+i%s+redo") or norm:match("^how%s+can%s+i%s+redo") then return true end
    if (norm:match("^how%s+do%s+i%s+") or norm:match("^how%s+can%s+i%s+"))
        and ContainsAny(norm, { "move", "drag", "position", "place", "verschiebe", "positionieren" })
    then
        return true
    end
    if (norm:match("^how%s+do%s+i%s+") or norm:match("^how%s+can%s+i%s+"))
        and ContainsAny(norm, {
            "change", "set", "make", "hide", "show", "turn on", "turn off", "enable", "disable",
            "lock", "unlock", "resize", "increase", "decrease", "scale", "scaling",
        })
        and ContainsAny(norm, {
            "text", "name", "hp", "health", "power", "mana", "castbar", "cast bar",
            "class resource", "class power", "combat timer", "totem", "raid frame", "party frame",
            "group frame", "ready check", "role icon", "range fade", "menu scale", "menu bigger",
            "menu smaller", "options scale", "ui scale", "raid", "party", "mythic raid",
            "players", "player count", "raid size",
        })
    then
        return true
    end
    if norm:match("^help%s+with%s+")
        and ContainsAny(norm, { "cooldown manager", "cooldownmanager", "essential cooldown", "essential cooldowns", "cdm" })
    then
        return true
    end
    if ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then
        return false
    end
    if norm:match("^explain%s+") or norm:match("^erklaere%s+") then return true end
    if norm:match("^what%s+does%s+") or norm:match("^what%s+is%s+") or norm:match("^what%s+are%s+") then return true end
    if norm:match("^where%s+do%s+") or norm:match("^where%s+can%s+") or norm:match("^where%s+to%s+") then return true end
    if norm:match("^where%s+is%s+") or norm:match("^where%s+are%s+") then return true end
    if norm:match("^show%s+me%s+.+settings") or norm:match("^show%s+me%s+.+options") then return true end
    if norm:match("^wo%s+ist%s+") or norm:match("^wo%s+kann%s+") or norm:match("^was%s+ist%s+") then return true end
    return false
end

local function StartsWithMutationCommand(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if LooksLikeKnowledgeQuestionPrefix(norm) then return false end
    for i = 1, #MUTATION_TERMS do
        local term = Normalize(MUTATION_TERMS[i])
        if norm == term or norm:sub(1, #term + 1) == term .. " " then return true end
    end
    return false
end

local function LooksLikeKnowledgeRequest(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    return ContainsAny(norm, {
        "help", "why", "where", "where is", "where are", "what", "what is", "what are", "how", "how do",
        "search", "find", "faq", "explain", "show me",
        "hilfe", "warum", "wo", "wo ist", "wie", "suche", "finde", "erklaere",
    })
end

local function LooksLikeKnowledgeFirstRequest(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if LooksLikeKnowledgeQuestionPrefix(norm) then return true end
    if ContainsAny(norm, MUTATION_TERMS) then return false end
    if ContainsAny(norm, { "open", "go to", "show settings", "show me settings", "oeffne" }) then return false end
    if ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then return false end
    return ContainsAny(norm, {
        "search", "find", "where", "where is", "where are", "faq", "explain",
        "suche", "finde", "wo", "wo ist", "erklaere",
    })
end

local function LooksLikeChangelogKnowledgeRequest(text)
    if A.Knowledge and type(A.Knowledge.LooksLikeChangelogQuestion) == "function" then
        return A.Knowledge.LooksLikeChangelogQuestion(text) == true
    end
    local norm = Normalize(text)
    if norm == "" then return false end
    if ContainsAny(norm, { "open changelog", "close changelog", "toggle changelog", "oeffne changelog" }) then return false end
    if ContainsAny(norm, { "release notes", "patch notes", "build notes", "latest changes", "changelog", "change log", "was ist neu", "was hat sich geaendert" }) then return true end
    if ContainsAny(norm, { "what changed", "what is new", "whats new" })
        and (norm:find("%d+%.%d+") or ContainsAny(norm, { "release", "version", "preview", "alpha", "beta", "patch", "build" })) then
        return true
    end
    return false
end

local function KnowledgeNoMatch(text)
    if A.Knowledge and type(A.Knowledge.NoMatch) == "function" then
        local result = A.Knowledge.NoMatch(text)
        if A.RecordNoMatch then A.RecordNoMatch(text, result, "knowledge") end
        return result
    end
    return nil
end

local function IsGermanConversation(text)
    return ContainsAny(text, {
        "hallo", "moin", "servus", "danke", "danke dir", "bitte", "wie gehts", "wie geht es dir", "alles gut",
        "wer bist du", "was bist du", "witz", "normal reden", "einfach reden", "besser in wow",
        "besser bei wow", "wie werde ich besser", "klassenguide", "talente", "spielweise",
    })
end

local function LooksLikeBugReportRequest(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if ContainsAny(norm, {
        "bug report", "report bug", "report a bug", "report bugs", "submit bug", "submit a bug",
        "bug feedback", "bug ticket", "where report bug", "where do i report bugs", "where can i report bugs",
        "where to report bugs", "how do i report bugs", "how to report bugs", "i found a bug",
        "i found bug", "found a bug", "found bug", "i found an issue", "found an issue",
        "report issue", "report an issue", "submit issue", "submit an issue", "open issue",
        "leave comment", "leave a comment", "curseforge comment",
        "bug melden", "bugs melden", "fehler melden", "problem melden", "bug reporten",
        "fehler reporten", "problem reporten", "wo melde ich bugs", "wo kann ich bugs melden",
        "wo melde ich fehler", "wo kann ich fehler melden", "wie melde ich bugs", "wie melde ich fehler",
        "ich habe einen bug gefunden", "ich habe ein bug gefunden", "ich habe einen fehler gefunden",
        "bug gefunden", "fehler gefunden", "kommentar auf curseforge",
    }) then
        return true
    end

    local hasBugWord = ContainsAny(norm, { "bug", "bugs", "issue", "issues", "problem", "problems", "fehler", "probleme" })
    local hasReportWord = ContainsAny(norm, {
        "report", "reporting", "submit", "where", "where do", "where can", "how do", "how to",
        "found", "found a", "i found", "comment", "curseforge",
        "melden", "melde", "reporten", "gefunden", "kommentar",
    })
    return hasBugWord and hasReportWord
end

local function LooksLikeGuidedTourRequest(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if ContainsAny(norm, {
        "guided setup", "setup guide", "start guide", "start tour", "tour guide",
        "show me around", "walk me through", "getting started", "beginner guide",
        "beginner setup", "onboarding", "first time msuf", "new to msuf",
        "never used msuf", "never used this addon", "start with msuf",
        "how do i start with msuf", "setup hilfe", "einsteiger", "anfanger",
        "neu in msuf", "noch nie msuf", "zeig mir msuf", "fuehrung",
    }) then
        return true
    end
    if ContainsAny(norm, { "guide me", "help me setup", "help me set up", "help me configure", "help me build" })
        and ContainsAny(norm, { "msuf", "unit frame", "unit frames", "frames", "layout", "addon", "setup", "beginner", "new", "first", "never used" }) then
        return true
    end
    if ContainsAny(norm, { "i am new", "im new", "i'm new", "new user", "first time", "never used" })
        and ContainsAny(norm, { "msuf", "unit frame", "unit frames", "addon" }) then
        return true
    end
    return false
end

local SCOPED_HELP_SCOPE_TERMS = {
    "player", "player frame", "target", "target frame", "focus", "focus frame", "pet", "pet frame",
    "boss", "boss frame", "boss frames", "castbar", "castbars", "cast bar", "cast bars",
    "bar", "bars", "texture", "textures", "color", "colors", "font", "fonts",
    "profile", "profiles", "group", "group frame", "group frames", "party", "party frame",
    "party frames", "raid", "raid frame", "raid frames", "layout", "health text",
    "group text", "indicator", "indicators", "corner indicator", "corner indicators",
    "class resource", "class resources", "class power", "gameplay", "status icon",
    "status icons", "text slot", "text slots", "copy", "export", "import",
    "spieler", "ziel", "fokus", "begleiter", "gruppe", "gruppenframe", "gruppenframes",
    "profil", "profile", "farben", "farbe", "schrift", "zauberleiste",
}

local SCOPED_HELP_INTENT_TERMS = {
    "help", "help for", "help with", "help me with", "commands for", "show commands for",
    "what can i change", "what settings can i change", "what can i do",
    "what can i change here", "what can i do here", "how do profiles work",
    "hilfe", "hilfe fuer", "hilfe mit", "befehle fuer", "was kann ich aendern",
}

local function LooksLikeScopedHelpKnowledgeRequest(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    if ContainsAny(norm, { "what did you change", "what changed", "what was changed", "last change", "previous change" }) then return false end
    if ContainsAny(norm, { "open", "go to", "show settings", "show me settings", "oeffne" }) then return false end
    return ContainsAny(norm, SCOPED_HELP_INTENT_TERMS) and ContainsAny(norm, SCOPED_HELP_SCOPE_TERMS)
end

local function BugReportReply(text)
    local german = IsGermanConversation(text) or ContainsAny(text, {
        "bug melden", "fehler", "problem melden", "wo melde", "wo kann", "wie melde",
        "gefunden", "kommentar auf curseforge",
    })
    if german then
        return {
            text = "Danke, dass du es melden willst. Es waere super, wenn du den Bug reportest, damit ich ihn reproduzieren kann.\nDiscord: " .. DISCORD_INVITE .. "\nAlternativ kannst du auf der MSUF CurseForge-Seite einen Kommentar hinterlassen: " .. CURSEFORGE_PAGE .. "\nHilfreich sind: dein genauer Assistant-Text, die offene MSUF-Seite, was du erwartet hast und was wirklich passiert ist.",
            status = "info",
            summary = "Assistant bug report help",
        }
    end
    return {
        text = "Thanks for wanting to report it. That would really help MSUF development, especially if I can reproduce it.\nDiscord: " .. DISCORD_INVITE .. "\nAlternatively, you can leave a comment on the MSUF CurseForge page: " .. CURSEFORGE_PAGE .. "\nHelpful details: the exact Assistant text, the open MSUF page, what you expected, and what actually happened.",
        status = "info",
        summary = "Assistant bug report help",
    }
end

local function NextConversationJoke(german)
    local jokes = german and WOW_JOKES_DE or WOW_JOKES_EN
    if #jokes == 0 then return nil end

    local key = german and "lastGermanJokeIndex" or "lastEnglishJokeIndex"
    local index = 1
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        index = (tonumber(ctx[key]) or 0) + 1
        if index > #jokes then index = 1 end
        ctx[key] = index
    end
    return jokes[index]
end

local function HumanConversationReply(text)
    local norm = Normalize(text)
    if norm == "" then return nil end
    local german = IsGermanConversation(norm)

    if ContainsAny(norm, {
        "tell me a joke", "tell joke", "tell me another joke", "another joke", "say something funny", "make me laugh", "joke", "jokes",
        "erzaehl mir einen witz", "erzaehle mir einen witz", "erzaehl einen witz",
        "erzaehle einen witz", "mach einen witz", "noch einen witz", "noch ein witz", "naechster witz", "witz",
    }) then
        return {
            text = NextConversationJoke(german) or (german and "Klar. MSUF ist bereit fuer den naechsten Witz." or "Sure. MSUF is ready for the next joke."),
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if ContainsAny(norm, {
        "can we talk", "talk to me", "chat with me", "normal talk", "talk normally", "just talk",
        "small talk", "normal reden", "einfach reden", "lass uns reden", "kannst du normal reden",
    }) then
        return {
            text = german
                and "Ja, kurz schon. Ich bin aber ein lokaler MSUF Assistant, keine externe KI. Ich kann dir MSUF erklaeren, Einstellungen aendern, Fehlerwege nennen oder dich bei WoW-Fragen auf aktuelle Seiten wie Wowhead verweisen."
                or "Yes, a little. I am still a local MSUF Assistant, not an external AI. I can explain MSUF, change settings, help with bug-report paths, or point general WoW questions to current sites like Wowhead.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if ContainsAny(norm, {
        "get better at wow", "better at wow", "improve at wow", "improve in wow", "wow improvement",
        "learn wow", "wow guide", "guide for wow", "class guide", "rotation guide", "talent guide",
        "best talents", "best build", "dps guide", "healer guide", "tank guide", "raid guide",
        "mythic plus guide", "m plus guide", "m+ guide", "how do i play my class",
        "where can i find wow guides", "wowhead",
        "besser in wow", "besser bei wow", "wow besser", "wie werde ich besser",
        "wie werde ich besser in wow", "klassenguide", "klassen guide", "talente",
        "rotation", "spielweise", "wow guide deutsch",
    }) then
        return {
            text = german
                and ("Dabei kann ich nur begrenzt helfen, weil MSUF offline laeuft und keine aktuellen Klassen- oder Patch-Guides laden kann. Fuer aktuelle WoW-Guides schau am besten auf Wowhead: " .. WOWHEAD_GUIDES .. ". Bei UI-Setup, Unit Frames, Sichtbarkeit, Texten und MSUF-Profilen helfe ich dir direkt hier.")
                or ("I can only help a little with that, because MSUF runs offline and cannot keep live class or patch guides updated. For current WoW guides, check Wowhead: " .. WOWHEAD_GUIDES .. ". For UI setup, unit frames, visibility, texts, and MSUF profiles, I can help directly here."),
            status = "info",
            summary = "General WoW help",
        }
    end

    if ContainsAny(norm, { "how are you", "how are you doing", "are you ok", "you good", "wie gehts", "wie geht es dir", "alles gut", "gehts dir gut" }) then
        return {
            text = german
                and "Mir geht es gut. Ich bin bereit fuer MSUF. Sag mir einfach, welche Einstellung oder welches Frame du aendern willst."
                or "I am ready to help with MSUF. Tell me the setting or frame you want to change, or ask where something is.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if ContainsAny(norm, { "hi", "hello", "hey", "good morning", "good evening", "hallo", "moin", "servus" }) then
        return {
            text = german
                and "Hallo. Ich bin der lokale MSUF Assistant. Sag mir, was du in MSUF aendern oder finden willst."
                or "Hi. I am the local MSUF Assistant. Tell me what you want to change or find in MSUF.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if ContainsAny(norm, { "thanks", "thank you", "thx", "danke", "danke dir" }) then
        return {
            text = german
                and "Gerne. Sag mir einfach den naechsten MSUF-Wunsch."
                or "You are welcome. Send the next MSUF change whenever you are ready.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if ContainsAny(norm, { "who are you", "what are you", "wer bist du", "was bist du" }) then
        return {
            text = german
                and "Ich bin der lokale MSUF Assistant. Ich kann echte registrierte MSUF-Funktionen aendern, Seiten erklaeren und bei unklaren Befehlen nachfragen. Registrierte Aura-Regler funktionieren, nicht angebundene Aura-Backend-Bereiche bleiben blockiert."
                or "I am the local MSUF Assistant. I can change real registered MSUF controls, explain pages, and ask when a command is ambiguous. Registered Aura controls work; Aura backend areas that are not registered yet stay blocked.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    return nil
end

local function UnsupportedAuraReply(text)
    local norm = Normalize(text)
    local parser = A.Parser or {}
    if type(parser.CopyCommandExcludesAuras) == "function" and parser.CopyCommandExcludesAuras(norm) then return nil end
    if ContainsAny(norm, { "debuff stripe", "debuff stripes" }) then return nil end
    if ContainsAny(norm, { "dispel overlay", "unitframe dispel overlay", "unit frame dispel overlay" }) then return nil end
    if not ContainsAny(norm, AURA_OUT_OF_SCOPE_TERMS)
        and not (ContainsAny(norm, AURA_BUFF_TERMS) and ContainsAny(norm, AURA_BUFF_CONTEXT_TERMS))
    then
        return nil
    end
    local german = ContainsAny(norm, {
        "auren", "gruppenauren", "hilfe", "warum", "wo", "oeffne", "suche", "finde",
        "einschalten", "ausschalten", "aktivieren", "deaktivieren", "anzeigen", "verstecken",
    })
    return {
        kind = "unsupported",
        status = "info",
        summary = "Aura command is not registered yet.",
        text = german
            and "Ich konnte diesen Aura-Befehl noch nicht sicher matchen. Registrierte Aura-Regler wie Icon-Groesse, Anzahl, Wachstum, Cooldown-/Stack-Text, Filter, Blacklist und Quick-Presets funktionieren. Aura-Copy und nicht angebundene Backend-Bereiche bleiben blockiert."
            or "I could not safely match that Aura command yet. Registered Aura controls such as icon size, count, growth, cooldown and stack text, filters, blacklist, quick presets, and Group Aura copy can be changed. Aura backend areas that are not registered yet stay blocked.",
    }
end

local function FriendlyNoMatch(text)
    local noMatch = KnowledgeNoMatch(text)
    if noMatch then return noMatch end
    local result = {
        text = "I could not safely match that MSUF command yet. I will not guess at settings. Try the frame or page plus the exact control, for example 'set player width to 300', 'turn off raid range fade', or 'set target buff icon size to 30'. If that wording should work, send the exact text in Discord: " .. DISCORD_INVITE,
        status = "info",
        summary = "Assistant no match",
    }
    if A.RecordNoMatch then A.RecordNoMatch(text, result, "router") end
    return result
end

local function IsNoClueResult(result)
    if type(result) ~= "table" then return true end
    local msg = tostring(result.text or "")
    if result.kind == "unknown" and (msg == "" or msg:find("I do not know that setting yet", 1, true)) then return true end
    if result.status == "failed" and msg:find("I do not know that setting yet", 1, true) then return true end
    if result.status == "failed" and msg:find("could not parse", 1, true) then return true end
    return false
end

local function IsUnknownResult(result)
    if type(result) ~= "table" then return true end
    if result.kind == "unknown" then return true end
    local msg = tostring(result.text or "")
    if result.status == "failed" and msg:find("do not know", 1, true) then return true end
    if result.status == "failed" and msg:find("could not parse", 1, true) then return true end
    if result.status == "failed" and msg:find("not registered", 1, true) then return true end
    if result.status == "failed" and msg:find("unsupported", 1, true) then return true end
    return false
end

local function IsAmbiguousResult(result)
    return type(result) == "table" and (result.kind == "ambiguous" or result.status == "ambiguous")
end

local function SnapshotPendingState()
    local ctx = A.GetContext and A.GetContext()
    return {
        pendingConfirmation = A.pendingConfirmation,
        pendingChoices = A.pendingChoices,
        pendingFlow = A.pendingFlow,
        ctx = ctx,
        ctxPendingConfirmation = ctx and ctx.pendingConfirmation,
        ctxPendingChoices = ctx and ctx.pendingChoices,
        ctxPendingFlow = ctx and ctx.pendingFlow,
    }
end

local function RestorePendingState(state)
    if type(state) ~= "table" then return end
    A.pendingConfirmation = state.pendingConfirmation
    A.pendingChoices = state.pendingChoices
    A.pendingFlow = state.pendingFlow
    local ctx = state.ctx
    if type(ctx) == "table" then
        ctx.pendingConfirmation = state.ctxPendingConfirmation
        ctx.pendingChoices = state.ctxPendingChoices
        ctx.pendingFlow = state.ctxPendingFlow
    end
end


local function HasPendingAssistantState()
    if A.pendingConfirmation ~= nil then return true end
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return true end
    if type(A.pendingFlow) == "table" then return true end
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        if ctx.pendingConfirmation ~= nil then return true end
        if type(ctx.pendingChoices) == "table" and #ctx.pendingChoices > 0 then return true end
        if ctx.pendingFlow ~= nil then return true end
    end
    return false
end

local function ShouldSkipContext(text)
    local norm = Normalize(text)
    if norm == "" then return true end
    if ContainsAny(norm, FLOW_TERMS) then return true end
    if ContainsAny(norm, NAV_HELP_TERMS) then return true end
    if ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then return true end
    if ContainsAny(norm, EXPLICIT_DOMAIN_TERMS) then return true end
    if ContainsAny(norm, {
        "it", "that", "this", "same", "do it", "do that", "again", "more", "less",
        "opposite", "other way", "hide it", "clear it", "remove it", "move it",
    }) then return true end
    if ContainsAny(norm, {
        "unitframe", "unitframes", "unit frame", "unit frames",
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    }) then return true end
    local parser = A.Parser or {}
    if type(parser.DetectUnits) == "function" and #(parser.DetectUnits(norm) or {}) > 0 then return true end
    if type(parser.DetectGroups) == "function" and #(parser.DetectGroups(norm) or {}) > 0 then return true end
    return false
end

local function CurrentPageContext()
    local key = M and M.activeKey
    if type(key) ~= "string" or key == "" then return nil end
    return PAGE_CONTEXT[key]
end

local function CurrentGroupScopePrefix()
    local scope = M and M.gfScope
    if type(scope) ~= "string" or scope == "" then return nil end
    scope = Normalize(scope)
    return GROUP_SCOPE_PREFIXES[scope]
end

local function AddUnique(out, value)
    value = Trim(value)
    if value == "" then return end
    for i = 1, #out do if out[i] == value then return end end
    out[#out + 1] = value
end

local function ContextPrefixes(ctx)
    local prefixes = {}
    local key = M and M.activeKey
    if GROUP_CONTEXT_PAGES[key] then
        AddUnique(prefixes, CurrentGroupScopePrefix() or "")
    end
    if ctx and ctx.prefix then AddUnique(prefixes, ctx.prefix) end
    return prefixes
end

local function StripBooleanWords(text)
    local out = Normalize(text)
    out = out:gsub("^turn%s+", "")
    out = out:gsub("^set%s+", "")
    out = out:gsub("^make%s+", "")
    out = out:gsub("^change%s+", "")
    out = out:gsub("^increase%s+", "")
    out = out:gsub("^decrease%s+", "")
    out = out:gsub("^raise%s+", "")
    out = out:gsub("^lower%s+", "")
    out = out:gsub("^detach%s+", "")
    out = out:gsub("^attach%s+", "")
    out = out:gsub("^undock%s+", "")
    out = out:gsub("^dock%s+", "")
    out = out:gsub("^on%s+", "")
    out = out:gsub("^off%s+", "")
    out = out:gsub("^enable%s+", "")
    out = out:gsub("^disable%s+", "")
    out = out:gsub("^einschalten%s+", "")
    out = out:gsub("^ausschalten%s+", "")
    out = out:gsub("^einblenden%s+", "")
    out = out:gsub("^ausblenden%s+", "")
    out = out:gsub("^show%s+", "")
    out = out:gsub("^hide%s+", "")
    out = out:gsub("^erhoehe%s+", "")
    out = out:gsub("^erhoehen%s+", "")
    out = out:gsub("^senke%s+", "")
    out = out:gsub("^reduziere%s+", "")
    out = out:gsub("^abkoppeln%s+", "")
    out = out:gsub("^ankoppeln%s+", "")
    out = out:gsub("%s+on$", "")
    out = out:gsub("%s+off$", "")
    out = out:gsub("%s+enabled$", "")
    out = out:gsub("%s+disabled$", "")
    out = out:gsub("%s+an$", "")
    out = out:gsub("%s+aus$", "")
    return Trim(out)
end


local function StripLeadingCommand(text)
    local out = Normalize(text)
    out = out:gsub("^set%s+", "")
    out = out:gsub("^change%s+", "")
    out = out:gsub("^make%s+", "")
    out = out:gsub("^increase%s+", "")
    out = out:gsub("^decrease%s+", "")
    out = out:gsub("^raise%s+", "")
    out = out:gsub("^lower%s+", "")
    out = out:gsub("^detach%s+", "")
    out = out:gsub("^attach%s+", "")
    out = out:gsub("^undock%s+", "")
    out = out:gsub("^dock%s+", "")
    out = out:gsub("^erhoehe%s+", "")
    out = out:gsub("^erhoehen%s+", "")
    out = out:gsub("^senke%s+", "")
    out = out:gsub("^reduziere%s+", "")
    out = out:gsub("^abkoppeln%s+", "")
    out = out:gsub("^ankoppeln%s+", "")
    out = out:gsub("^use%s+", "")
    out = out:gsub("^select%s+", "")
    out = out:gsub("^choose%s+", "")
    return Trim(out)
end

local function LeadingRelativeCommand(text)
    local norm = Normalize(text)
    if ContainsAny(norm, { "decrease", "lower", "reduce", "smaller", "shrink", "less", "senke", "reduziere", "kleiner", "weniger" }) then
        return "decrease"
    end
    if ContainsAny(norm, { "increase", "raise", "higher", "more", "larger", "bigger", "grow", "erhoehe", "erhoehen", "hoeher", "groesser" }) then
        return "increase"
    end
    return nil
end

local function AddBooleanContextVariants(variants, prefix, text)
    local norm = Normalize(text)
    local noun = StripBooleanWords(text)
    if noun == "" then return end
    if ContainsAny(norm, { "off", "disable", "disabled", "hide", "aus", "deaktivieren", "ausschalten", "verstecken", "ausblenden" }) then
        AddUnique(variants, "turn off " .. prefix .. " " .. noun)
        AddUnique(variants, "disable " .. prefix .. " " .. noun)
    elseif ContainsAny(norm, { "on", "enable", "enabled", "show", "an", "aktivieren", "einschalten", "anzeigen", "einblenden" }) then
        AddUnique(variants, "turn on " .. prefix .. " " .. noun)
        AddUnique(variants, "enable " .. prefix .. " " .. noun)
    end
end

local function ContextualVariants(text)
    if ShouldSkipContext(text) then return nil end
    local ctx = CurrentPageContext()
    if not ctx or not ctx.prefix then return nil end
    local norm = Normalize(text)
    local variants = {}
    local prefixes = ContextPrefixes(ctx)
    local prefix = prefixes[1] or ctx.prefix

    if M.activeKey == "profiles" then
        if norm == "export" or norm == "export profile" then
            AddUnique(variants, "export current profile")
        elseif norm == "import" or norm == "import profile" then
            AddUnique(variants, "import profile")
        elseif norm == "copy" or norm == "copy profile" then
            AddUnique(variants, "copy current profile")
        else
            AddUnique(variants, prefix .. " " .. text)
        end
    elseif M.activeKey == "opt_castbar" then
        local noun = StripLeadingCommand(text)
        local relativeVerb = LeadingRelativeCommand(text)
        AddBooleanContextVariants(variants, "castbar", text)
        AddUnique(variants, "castbar " .. text)
        AddUnique(variants, "set castbar " .. text)
        if noun ~= "" and noun ~= Normalize(text) then
            if relativeVerb then AddUnique(variants, relativeVerb .. " castbar " .. noun) end
            AddUnique(variants, "set castbar " .. noun)
            AddUnique(variants, "change castbar " .. noun)
        end
        AddUnique(variants, "target castbar " .. text)
    elseif M.activeKey == "opt_bars" then
        local noun = StripLeadingCommand(text)
        local relativeVerb = LeadingRelativeCommand(text)
        AddBooleanContextVariants(variants, "bar", text)
        AddUnique(variants, "bar " .. text)
        AddUnique(variants, "set bar " .. text)
        if noun ~= "" and noun ~= Normalize(text) then
            if relativeVerb then AddUnique(variants, relativeVerb .. " bar " .. noun) end
            AddUnique(variants, "set bar " .. noun)
            AddUnique(variants, "change bar " .. noun)
        end
    elseif M.activeKey == "opt_fonts" then
        local noun = StripLeadingCommand(text)
        AddUnique(variants, "font " .. text)
        AddUnique(variants, "set font " .. text)
        if noun ~= "" and noun ~= Normalize(text) then
            AddUnique(variants, "set font " .. noun)
            AddUnique(variants, "change font " .. noun)
        end
    elseif M.activeKey == "opt_colors" then
        AddUnique(variants, text .. " color")
        AddUnique(variants, "set " .. text)
        AddUnique(variants, "global " .. text)
    else
        local noun = StripLeadingCommand(text)
        local relativeVerb = LeadingRelativeCommand(text)
        for i = 1, #prefixes do
            local scopedPrefix = prefixes[i]
            AddBooleanContextVariants(variants, scopedPrefix, text)
            AddUnique(variants, scopedPrefix .. " " .. text)
            AddUnique(variants, "set " .. scopedPrefix .. " " .. text)
            if noun ~= "" and noun ~= Normalize(text) then
                if relativeVerb then AddUnique(variants, relativeVerb .. " " .. scopedPrefix .. " " .. noun) end
                AddUnique(variants, "set " .. scopedPrefix .. " " .. noun)
                AddUnique(variants, "change " .. scopedPrefix .. " " .. noun)
            end
        end
    end
    return #variants > 0 and variants or nil
end

local function TryContext(text, coreHandler)
    if type(coreHandler) ~= "function" then return nil end
    local variants = ContextualVariants(text)
    if not variants then return nil end
    local basePending = SnapshotPendingState()
    local bestAmbiguous
    local bestAmbiguousPending
    for i = 1, #variants do
        MaybeYield()
        local result = coreHandler(variants[i])
        if result and not IsUnknownResult(result) then
            if not IsAmbiguousResult(result) then
                result.summary = result.summary or ("Current-page context: " .. tostring((CurrentPageContext() or {}).label or M.activeKey or "page"))
                return result
            end
            local ambiguousPending = SnapshotPendingState()
            RestorePendingState(basePending)
            bestAmbiguous = bestAmbiguous or result
            bestAmbiguousPending = bestAmbiguousPending or ambiguousPending
        else
            RestorePendingState(basePending)
        end
    end
    if bestAmbiguous and bestAmbiguousPending then RestorePendingState(bestAmbiguousPending) end
    return bestAmbiguous
end

local function MutationFallbackVariants(text)
    local norm = Normalize(text)
    local variants = {}
    if norm == "" then return variants end

    if ContainsAny(norm, { "frame outline", "frame border", "unitframe outline", "unitframe border" }) then
        AddUnique(variants, norm:gsub("frame%s+outline", "bar outline"))
        AddUnique(variants, norm:gsub("frame%s+border", "bar border"))
        AddUnique(variants, norm:gsub("unitframe%s+outline", "bar outline"))
        AddUnique(variants, norm:gsub("unitframe%s+border", "bar border"))
        AddUnique(variants, "global bar " .. norm)
    end

    if ContainsAny(norm, { "turn off", "turn on", "enable", "disable", "show", "hide", "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden" }) then
        AddUnique(variants, norm:gsub("^turn%s+off%s+", "disable "))
        AddUnique(variants, norm:gsub("^turn%s+on%s+", "enable "))
        AddUnique(variants, norm:gsub("^show%s+", "turn on "))
        AddUnique(variants, norm:gsub("^hide%s+", "turn off "))
        AddUnique(variants, norm:gsub("^disable%s+", "turn off "))
        AddUnique(variants, norm:gsub("^enable%s+", "turn on "))
        AddUnique(variants, norm:gsub("^ausschalten%s+", "turn off "))
        AddUnique(variants, norm:gsub("^ausblenden%s+", "turn off "))
        AddUnique(variants, norm:gsub("^einschalten%s+", "turn on "))
        AddUnique(variants, norm:gsub("^einblenden%s+", "turn on "))
    end

    return variants
end

local function TryMutationFallbacks(text, coreHandler)
    if type(coreHandler) ~= "function" then return nil end
    local variants = MutationFallbackVariants(text)
    local limit = math.min(#variants, 4)
    for i = 1, limit do
        MaybeYield()
        if variants[i] ~= Normalize(text) then
            local result = coreHandler(variants[i])
            if result and not IsUnknownResult(result) then
                result.summary = result.summary or "Mutation fallback alias."
                return result
            end
        end
    end
    return nil
end

function A.RouteInput(text, coreHandler)
    text = Trim(text)
    if text == "" then return nil end

    local hasCore = type(coreHandler) == "function"
    local coreCache = {}
    local function Core(value)
        if not hasCore then return nil end
        value = Trim(value)
        if coreCache[value] == nil then
            local result = coreHandler(value)
            coreCache[value] = result or false
        end
        return coreCache[value] ~= false and coreCache[value] or nil
    end

    -- Pending confirmations/choices/flows must always win. The core handler owns those.
    if hasCore and (HasPendingAssistantState() or (ContainsAny(text, FLOW_TERMS) and not LooksLikeKnowledgeQuestionPrefix(text))) then
        local pendingResult = Core(text)
        if pendingResult and (not IsUnknownResult(pendingResult) or HasPendingAssistantState()) then return pendingResult end
    end

    if LooksLikeBugReportRequest(text) then return BugReportReply(text) end

    if LooksLikeGuidedTourRequest(text) and hasCore then
        local guidedResult = Core(text)
        if guidedResult and not IsUnknownResult(guidedResult) then return guidedResult end
    end

    local humanResult = HumanConversationReply(text)
    if humanResult then return humanResult end

    if hasCore and LooksLikeExactAssistantKey(text) and (LooksLikeMutation(text) or StartsWithMutationCommand(text)) then
        local exactKeyResult = Core(text)
        if exactKeyResult and not IsUnknownResult(exactKeyResult) then return exactKeyResult end
    end

    if not LooksLikeKnowledgeQuestionPrefix(text) then
        local parser = A.Parser or {}
        local broadAnchor = parser.ParseBroadHumanAnchorTargetAnswer and parser.ParseBroadHumanAnchorTargetAnswer(Normalize(text), text)
        if broadAnchor then return broadAnchor end
    end

    if hasCore and not LooksLikeKnowledgeQuestionPrefix(text)
        and not (Normalize(text):find("%d+%.%d+") or ContainsAny(text, {
            "release", "version", "preview", "alpha", "beta", "patch", "build", "changelog", "change log",
        }))
        and ContainsAny(text, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then
        local followupResult = Core(text)
        if followupResult and not IsUnknownResult(followupResult) then return followupResult end
    end

    if LooksLikeScopedHelpKnowledgeRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if LooksLikeKnowledgeFirstRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    local parser = A.Parser or {}
    local normForScope = Normalize(text)
    local hasClassPowerScope = (type(parser.CLASS_POWER_TERMS) == "table" and ContainsAny(normForScope, parser.CLASS_POWER_TERMS))
        or ContainsAny(normForScope, { "resource numbers", "resource number", "resource text", "resource texts" })
    local hasExplicitScope = ContainsAny(normForScope, {
        "unitframe", "unitframes", "unit frame", "unit frames",
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    })
        or hasClassPowerScope
        or (type(parser.DetectUnits) == "function" and #(parser.DetectUnits(text) or {}) > 0)
        or (type(parser.DetectGroups) == "function" and #(parser.DetectGroups(text) or {}) > 0)
    if hasExplicitScope and hasCore and not LooksLikeKnowledgeFirstRequest(text) then
        local scopedCoreResult = Core(text)
        if scopedCoreResult and not IsUnknownResult(scopedCoreResult) then return scopedCoreResult end
    end

    -- Short page-local commands become useful before falling back to broad global matching.
    local contextResult = TryContext(text, Core)
    if contextResult and not IsUnknownResult(contextResult) then return contextResult end

    local coreResult
    if (LooksLikeMutation(text) or StartsWithMutationCommand(text)) and hasCore then
        coreResult = Core(text)
        if not IsUnknownResult(coreResult) then return coreResult end
    end

    -- Release-note questions must not be mistaken for "what did you just change?" follow-ups.
    if LooksLikeChangelogKnowledgeRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if LooksLikeKnowledgeFirstRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if hasCore then
        coreResult = coreResult or Core(text)
        if not IsUnknownResult(coreResult) then return coreResult end
    end

    if LooksLikeBareLookup(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    -- Mutation-like commands must not be swallowed by Search/FAQ fallback.
    -- If a setting/action command failed, return the parser failure or suggestions instead of a help article.
    if LooksLikeMutation(text) or StartsWithMutationCommand(text) then
        local fallbackResult = TryMutationFallbacks(text, Core)
        if fallbackResult and not IsUnknownResult(fallbackResult) then return fallbackResult end
        local auraUnsupported = UnsupportedAuraReply(text)
        if auraUnsupported then return auraUnsupported end
        if IsNoClueResult(coreResult) then return FriendlyNoMatch(text) end
        return coreResult or { text = "I could not apply that command. Try being more specific or ask for help.", status = "failed" }
    end

    if A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        if LooksLikeKnowledgeRequest(text) then
            local noMatch = KnowledgeNoMatch(text)
            if noMatch then return noMatch end
        end
    end

    local auraUnsupported = UnsupportedAuraReply(text)
    if auraUnsupported then return auraUnsupported end

    if IsNoClueResult(coreResult) then return FriendlyNoMatch(text) end
    return coreResult or FriendlyNoMatch(text)
end
