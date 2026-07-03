local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local R = A.RouterPrivate or {}
A.RouterPrivate = R

--- Shell/Menu2/Assistant/MSUF_AssistantRouter.lua
---
--- Conversation router that decides whether an input should be treated as a
--- pending confirmation/choice, contextual assistant command, knowledge/help
--- request, or friendly no-match response. It intentionally runs before the
--- heavy parser fallback so short page-local commands can resolve quickly.
---
--- Keep routing heuristics conservative: mutation-like text should reach the
--- parser, while pure help/conversation can be answered here.

function R.Trim(text)    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

R.COMMAND_TERMS = {    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset", "copy",
    "add", "put", "clear", "increase", "decrease", "raise", "lower", "bump", "grow", "shrink", "detach", "attach", "anchor", "follow", "undock", "dock", "embed",
    "export", "import", "create", "delete", "remove", "switch", "assign", "rename", "open", "close", "toggle",
    "diagnose", "why", "help", "undo", "redo", "yes", "cancel", "next", "back", "finish", "start", "stop", "enter", "leave",
    "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken",
    "einblenden", "ausblenden", "verschiebe", "verschieben", "setze", "stelle", "erhoehe", "erhoehen", "senke", "reduziere",
    "abkoppeln", "ankoppeln", "einbetten", "oeffne", "suche", "finde",
}
R.COLOR_TERMS = {    "red", "green", "blue", "yellow", "white", "black", "orange", "purple", "pink", "gold", "gray", "grey",
    "rot", "gruen", "blau", "gelb", "weiss", "schwarz", "lila", "grau",
}
R.FLOW_TERMS = {    "yes", "y", "ja", "confirm", "apply", "cancel", "no", "nein", "abort", "stop", "next", "back", "finish", "undo", "redo",
}
R.DISCORD_INVITE = "https://discord.gg/2Gf9b2Wprz"
R.CURSEFORGE_PAGE = "https://www.curseforge.com/wow/addons/midnightsimpleunitframes"
R.WOWHEAD_GUIDES = "https://www.wowhead.com/guides"
R.WOW_JOKES_EN = {    "Sure. Why did the unit frame join the raid? It wanted a stable group.",
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
R.IMMEDIATE_SHORT_CONVERSATION = {
    hi = true,
    hello = true,
    hey = true,
    hallo = true,
    moin = true,
    servus = true,
    thx = true,
    danke = true,
}
R.IMMEDIATE_CONVERSATION_PHRASES = {
    "how are you", "how are you doing", "are you ok", "you good", "wie gehts", "wie geht es dir", "alles gut", "gehts dir gut",
    "good morning", "good evening",
    "thanks", "thank you", "danke dir",
    "who are you", "what are you", "wer bist du", "was bist du",
    "tell me a joke", "tell joke", "tell me another joke", "another joke", "say something funny", "make me laugh", "joke", "jokes",
    "what can you do", "what can i ask", "what can i ask you", "what can the assistant do",
    "assistant help", "show commands", "what commands", "which commands", "available commands",
    "chatgpt", "chat gpt", "ai assistant", "ai chat", "like chatgpt", "like chat gpt",
}

R.MUTATION_TERMS = {    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset",
    "copy", "export", "import", "create", "delete", "remove", "add", "put", "clear", "switch", "assign", "rename", "close", "toggle",
    "increase", "decrease", "raise", "lower", "bump", "grow", "shrink", "detach", "attach", "anchor", "follow", "undock", "dock", "embed",
    "start", "stop", "enter", "leave", "select", "use", "apply",
    "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken",
    "einblenden", "ausblenden", "verschiebe", "verschieben", "setze", "stelle", "erhoehe", "erhoehen", "senke", "reduziere",
    "abkoppeln", "ankoppeln", "einbetten",
}
R.NAV_HELP_TERMS = {    "open", "go to", "where", "where is", "where are", "find", "search", "show me", "help", "why", "diagnose", "what", "how",
    "oeffne", "wo", "wo ist", "finde", "suche", "hilfe", "warum", "wie", "was", "was ist", "was kann", "was kannst",
}
R.EXPLICIT_DOMAIN_TERMS = {    "unitframe", "unitframes", "unit frame", "unit frames",
    "player", "target", "focus", "pet", "boss", "targettarget", "target of target", "focustarget", "focus target", "party", "raid", "group", "group frames",
    "spieler", "ziel", "fokus", "begleiter", "gruppe", "gruppenframes",
    "castbar", "cast bar", "auras", "aura", "buff", "debuff", "profile", "profiles", "class resource", "class power", "gameplay",
    "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus",
}

R.AURA_OUT_OF_SCOPE_TERMS = {    "aura", "auras", "auren",
    "group aura", "group auras", "gruppen aura", "gruppenauren",
}
R.AURA_BUFF_TERMS = { "buff", "buffs", "debuff", "debuffs" }
R.AURA_BUFF_CONTEXT_TERMS = {    "filter", "filters", "blacklist", "whitelist", "preset", "quick setup", "setup",
    "hidden", "hide", "show", "open", "help", "why", "where", "settings",
    "turn", "turn on", "turn off", "on", "off", "enable", "disable", "enabled", "disabled",
    "set", "change", "make", "size", "count", "max", "maximum", "cap", "caps", "limit", "limits",
    "icon", "icons", "per row", "growth", "spacing", "gap", "x offset", "y offset", "layer", "z layer", "frame level",
    "copy", "use", "kopieren", "kopiere", "uebernehme", "uebernehmen",
    "own", "mine", "only mine", "only player", "raid filter", "player filter",
    "stack", "cooldown", "duration", "duration bar", "timer bar", "pandemic",
}

R.PAGE_CONTEXT = {    uf_player = { prefix = "player", label = "Player" },
    uf_target = { prefix = "target", label = "Target" },
    uf_focus = { prefix = "focus", label = "Focus" },
    uf_pet = { prefix = "pet", label = "Pet" },
    uf_targettarget = { prefix = "targettarget", label = "Target of Target" },
    uf_focustarget = { prefix = "focustarget", label = "Focus Target" },
    uf_boss = { prefix = "boss", label = "Boss Frames" },
    opt_castbar = { prefix = "castbar", label = "Cast Bars" },
    opt_bars = { prefix = "bar", label = "Bars" },
    opt_colors = { prefix = "color", label = "Colors" },
    opt_fonts = { prefix = "font", label = "Fonts" },
    opt_misc = { prefix = "misc", label = "Miscellaneous" },
    modules = { prefix = "module", label = "Modules" },
    classpower = { prefix = "class resource", label = "Class Resources" },
    gameplay = { prefix = "gameplay", label = "Gameplay" },
    profiles = { prefix = "profile", label = "Profiles" },
    gf_layout = { prefix = "group", label = "Group Layout" },
    gf_bars = { prefix = "group text", label = "Group Health & Text" },
    gf_indicators = { prefix = "group indicator", label = "Group Status & Indicators" },
    gf_auras = { prefix = "group aura", label = "Group Auras" },
    auras3 = { prefix = "aura", label = "Auras" },
    auras3_buffs = { prefix = "aura buff", label = "Aura Buffs" },
    auras3_debuffs = { prefix = "aura debuff", label = "Aura Debuffs" },
    auras3_styling = { prefix = "aura style", label = "Aura Style" },
    auras3_filters = { prefix = "aura filter", label = "Aura Filters" },
}

R.GROUP_CONTEXT_PAGES = {    gf_layout = true,
    gf_bars = true,
    gf_indicators = true,
    gf_auras = true,
}

R.GROUP_SCOPE_PREFIXES = {    party = "party",
    raid = "raid",
    mythicraid = "mythic raid",
    mythic = "mythic raid",
    ["mythic raid"] = "mythic raid",
}

function R.Normalize(text)    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
    return R.Trim(text)
end

function R.MaybeYield()    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
end

function R.HasNormalizedPhrase(normalizedText, phrase)    phrase = R.Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. tostring(normalizedText or "") .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

function R.HasPhrase(text, phrase)    return R.HasNormalizedPhrase(R.Normalize(text), phrase)
end

function R.ContainsAny(text, words)    local normalizedText = R.Normalize(text)
    for i = 1, #(words or {}) do
        if R.HasNormalizedPhrase(normalizedText, words[i]) then return true end
    end
    if type(A.FuzzyPhraseMatch) == "function" then
        for i = 1, #(words or {}) do
            if A.FuzzyPhraseMatch(normalizedText, words[i]) then return true end
        end
    end
    return false
end

function R.IsExactGenericDiagnosticRequest(text)
    local norm = R.Normalize(text)
    return norm == "run checks"
        or norm == "run check"
        or norm == "run diagnostics"
        or norm == "run diagnostic"
        or norm == "health check"
        or norm == "run health check"
        or norm == "msuf status"
        or norm == "show msuf status"
        or norm == "assistant status"
        or norm == "show assistant status"
        or norm == "diagnostic report"
        or norm == "show diagnostic report"
        or norm == "support text"
        or norm == "show support text"
        or norm == "assistant support text"
        or norm == "show assistant support text"
end

function R.IsStandaloneCancelReply(text)    local norm = R.Normalize(text)
    return norm == "no"
        or norm == "no thanks"
        or norm == "cancel"
        or norm == "abort"
        or norm == "stop"
        or norm == "nein"
        or norm == "nein danke"
        or norm == "abbrechen"
end

function R.IsStandaloneFlowReply(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.IsStandaloneCancelReply(norm) then return true end
    return norm == "yes"
        or norm == "y"
        or norm == "yeah"
        or norm == "yep"
        or norm == "yup"
        or norm == "ja"
        or norm == "confirm"
        or norm == "apply"
        or norm == "apply it"
        or norm == "apply that"
        or norm == "do it"
        or norm == "do that"
        or norm == "fix it"
        or norm == "fix that"
        or norm == "ok"
        or norm == "okay"
        or norm == "next"
        or norm == "back"
        or norm == "finish"
        or norm == "stop"
        or norm == "abort"
        or norm == "undo"
        or norm == "redo"
        or norm == "undo last"
        or norm == "redo last"
end

R.exactAssistantKeyCache = nil
R.exactAssistantKeyCacheCount = 0
function R.LooksLikeExactAssistantKey(text)    local raw = tostring(text or "")
    if not raw:find("[%.%_]") then return false end
    local registry = A.Registry
    if not registry then return false end
    local settings = type(registry.AllSettings) == "function" and registry:AllSettings() or {}
    local actions = type(registry.AllActions) == "function" and registry:AllActions() or {}
    local count = #settings + #actions
    if type(R.exactAssistantKeyCache) ~= "table" or R.exactAssistantKeyCacheCount ~= count then
        R.exactAssistantKeyCache = {}
        R.exactAssistantKeyCacheCount = count
        for i = 1, #settings do
            local key = tostring(settings[i] and settings[i].key or ""):lower()
            if key ~= "" then R.exactAssistantKeyCache[key] = true end
        end
        for i = 1, #actions do
            local key = tostring(actions[i] and actions[i].key or ""):lower()
            if key ~= "" then R.exactAssistantKeyCache[key] = true end
        end
    end
    for token in raw:gmatch("[%w_%.]+") do
        if token:find("[%.%_]") and R.exactAssistantKeyCache[token:lower()] then return true end
    end
    return false
end

function R.LooksLikeBareLookup(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if norm:match("%d") then return false end
    if norm:match("#%x%x%x") then return false end
    for i = 1, #R.COMMAND_TERMS do
        if R.HasPhrase(norm, R.COMMAND_TERMS[i]) then return false end
    end
    for i = 1, #R.COLOR_TERMS do
        if R.HasPhrase(norm, R.COLOR_TERMS[i]) then return false end
    end
    return true
end


function R.LooksLikeMutation(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, { "help", "why", "where", "where is", "what", "how", "search", "find", "show commands", "hilfe", "warum", "wo", "suche", "finde" }) then
        return false
    end
    return R.ContainsAny(norm, R.MUTATION_TERMS)
end

function R.LooksLikeKnowledgeQuestionPrefix(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if norm:match("^how%s+do%s+i%s+undo") or norm:match("^how%s+can%s+i%s+undo") then return true end
    if norm:match("^how%s+do%s+i%s+redo") or norm:match("^how%s+can%s+i%s+redo") then return true end
    if norm:match("^can%s+i%s+undo") or norm:match("^can%s+you%s+undo") then return true end
    if norm:match("^can%s+i%s+redo") or norm:match("^can%s+you%s+redo") then return true end
    if (norm:match("^how%s+do%s+i%s+") or norm:match("^how%s+can%s+i%s+"))
        and R.ContainsAny(norm, { "move", "drag", "position", "place", "verschiebe", "positionieren" })
    then
        return true
    end
    if (norm:match("^how%s+do%s+i%s+") or norm:match("^how%s+can%s+i%s+"))
        and R.ContainsAny(norm, {
            "change", "set", "make", "hide", "show", "turn on", "turn off", "enable", "disable",
            "lock", "unlock", "resize", "increase", "decrease", "scale", "scaling",
        })
        and R.ContainsAny(norm, {
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
        and R.ContainsAny(norm, { "cooldown manager", "cooldownmanager", "essential cooldown", "essential cooldowns", "cdm" })
    then
        return true
    end
    if R.ContainsAny(norm, {
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
    if norm:match("^was%s+kann%s+") or norm:match("^was%s+kannst%s+") or norm:match("^wie%s+kann%s+") then return true end
    return false
end

function R.StartsWithMutationCommand(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.LooksLikeKnowledgeQuestionPrefix(norm) then return false end
    for i = 1, #R.MUTATION_TERMS do
        local term = R.Normalize(R.MUTATION_TERMS[i])
        if norm == term or norm:sub(1, #term + 1) == term .. " " then return true end
    end
    return false
end

function R.LooksLikeKnowledgeRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    return R.ContainsAny(norm, {
        "help", "why", "where", "where is", "where are", "what", "what is", "what are", "how", "how do",
        "search", "find", "faq", "explain", "show me",
        "hilfe", "warum", "wo", "wo ist", "wie", "suche", "finde", "erklaere",
        "was", "was ist", "was sind", "was kann", "was kannst",
    })
end

function R.LooksLikeKnowledgeFirstRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.LooksLikeKnowledgeQuestionPrefix(norm) then return true end
    if R.ContainsAny(norm, R.MUTATION_TERMS) then return false end
    if R.ContainsAny(norm, { "open", "go to", "show settings", "show me settings", "oeffne" }) then return false end
    if R.ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then return false end
    return R.ContainsAny(norm, {
        "search", "find", "where", "where is", "where are", "faq", "explain",
        "suche", "finde", "wo", "wo ist", "erklaere",
        "was ist", "was sind", "was kann", "was kannst",
    })
end

function R.LooksLikeDirectDefinitionQuestion(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then return false end
    if R.LooksLikeConcreteScopedValueRequest and R.LooksLikeConcreteScopedValueRequest(norm) then return false end
    if R.ContainsAny(norm, { "where", "where is", "where are", "where can", "where do", "how do i", "how can i", "how to" }) then return false end
    if norm:match("^what%s+is%s+") or norm:match("^what%s+are%s+")
        or norm:match("^what%s+does%s+") or norm:match("^explain%s+")
        or norm:match("^describe%s+")
    then
        return true
    end
    return false
end

function R.LooksLikeChangelogKnowledgeRequest(text)    if A.Knowledge and type(A.Knowledge.LooksLikeChangelogQuestion) == "function" then
        return A.Knowledge.LooksLikeChangelogQuestion(text) == true
    end
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, { "open changelog", "close changelog", "toggle changelog", "oeffne changelog" }) then return false end
    if R.ContainsAny(norm, { "release notes", "patch notes", "build notes", "latest changes", "changelog", "change log", "was ist neu", "was hat sich geaendert" }) then return true end
    if R.ContainsAny(norm, { "what changed", "what is new", "whats new" })
        and (norm:find("%d+%.%d+") or R.ContainsAny(norm, { "release", "version", "preview", "alpha", "beta", "patch", "build" })) then
        return true
    end
    return false
end

R.LOCAL_WOW_UI_TERMS = {    "gcd", "global cooldown", "global cool down",
    "unit frame", "unit frames", "unitframe", "unitframes", "player frame", "target frame",
    "focus frame", "pet frame", "boss frame", "boss frames",
    "party frame", "party frames", "raid frame", "raid frames", "group frame", "group frames",
    "nameplate", "nameplates", "enemy nameplate", "enemy nameplates",
    "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    "health bar", "health bars", "hp bar", "hp bars", "power bar", "power bars",
    "mana bar", "mana bars", "resource bar", "resource bars",
    "class resource", "class resources", "class power", "class powers",
    "ready check", "ready checks", "readycheck", "raid marker", "raid markers",
    "absorb", "absorbs", "absorb bar", "shield", "shields",
    "incoming heal", "incoming heals", "heal prediction", "healing prediction",
    "alpha", "opacity", "transparent", "transparency", "fade", "faded",
    "anchor", "anchors", "anchoring", "anchor point", "anchor points",
    "x offset", "y offset", "offset", "offsets",
    "scale", "scaling", "ui scale", "menu scale", "frame scale",
    "texture", "textures", "bar texture", "castbar texture", "cast bar texture",
    "font outline", "font shadow", "text shadow", "monochrome",
    "cooldown swipe", "cooldown text", "aura cooldown",
    "stack count", "stack text", "aura stack", "aura stacks",
    "growth direction", "grow direction", "per row", "columns",
    "click through", "click-through", "clickable", "locked", "unlocked",
    "interrupt", "interrupts", "kick", "kicks", "interrupting",
    "mouseover healing", "mouse over healing", "mouseover heal", "click casting", "click-casting",
    "focus target", "focustarget", "target of target", "targettarget",
    "range check", "range fade", "out of range", "in range", "melee range",
    "dispel", "dispels", "dispellable", "dispellable debuff", "dispellable debuffs",
    "threat", "aggro", "combat lockdown", "lockdown", "protected action",
}

R.LOCAL_WOW_UI_INTENT_TERMS = {    "what", "what is", "what are", "what does", "can msuf", "does msuf",
    "can this", "can it", "help", "explain", "how", "how do", "how can",
    "where", "where is", "where do", "where can", "mean", "easier to see",
}

function R.LooksLikeLocalWowUiKnowledgeRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    return R.ContainsAny(norm, R.LOCAL_WOW_UI_TERMS) and R.ContainsAny(norm, R.LOCAL_WOW_UI_INTENT_TERMS)
end

function R.KnowledgeNoMatch(text)    if A.Knowledge and type(A.Knowledge.NoMatch) == "function" then
        local result = A.Knowledge.NoMatch(text)
        if A.RecordNoMatch then A.RecordNoMatch(text, result, "knowledge") end
        return result
    end
    return nil
end

function R.IsGermanConversation(text)    return R.ContainsAny(text, {
        "hallo", "moin", "servus", "danke", "danke dir", "bitte", "wie gehts", "wie geht es dir", "alles gut",
        "wer bist du", "was bist du", "witz", "normal reden", "einfach reden", "besser in wow",
        "besser bei wow", "wie werde ich besser", "klassenguide", "talente", "spielweise",
        "was kannst du", "was kannst du alles", "was kann der assistant", "was kann der assistent",
        "welche befehle", "befehle gibt", "befehle anzeigen", "wie chatgpt", "chatgpt", "chat gpt",
        "ki assistant", "ki assistent", "rede ueber msuf", "reden ueber msuf", "ueber msuf reden",
        "rede ueber wow", "reden ueber wow", "ueber wow reden", "kannst du mit wow helfen",
        "wow hilfe", "hilfe mit wow", "interface kaputt", "ui kaputt", "addon kaputt",
    })
end

function R.LooksLikeBugReportRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, {
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

    local hasBugWord = R.ContainsAny(norm, { "bug", "bugs", "issue", "issues", "problem", "problems", "fehler", "probleme" })
    local hasReportWord = R.ContainsAny(norm, {
        "report", "reporting", "submit", "where", "where do", "where can", "how do", "how to",
        "found", "found a", "i found", "comment", "curseforge",
        "melden", "melde", "reporten", "gefunden", "kommentar",
    })
    return hasBugWord and hasReportWord
end

function R.LooksLikeGuidedTourRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, {
        "guided setup", "setup guide", "start guide", "start tour", "tour guide",
        "show me around", "walk me through", "getting started", "beginner guide",
        "beginner setup", "onboarding", "first time msuf", "new to msuf",
        "never used msuf", "never used this addon", "start with msuf",
        "how do i start with msuf", "setup hilfe", "einsteiger", "anfanger",
        "neu in msuf", "noch nie msuf", "zeig mir msuf", "fuehrung",
    }) then
        return true
    end
    if R.ContainsAny(norm, { "guide me", "help me setup", "help me set up", "help me configure", "help me build" })
        and R.ContainsAny(norm, { "msuf", "unit frame", "unit frames", "frames", "layout", "addon", "setup", "beginner", "new", "first", "never used" }) then
        return true
    end
    if R.ContainsAny(norm, { "i am new", "im new", "i'm new", "new user", "first time", "never used" })
        and R.ContainsAny(norm, { "msuf", "unit frame", "unit frames", "addon" }) then
        return true
    end
    return false
end

R.SCOPED_HELP_SCOPE_TERMS = {    "player", "player frame", "target", "target frame", "focus", "focus frame", "pet", "pet frame",
    "boss", "boss frame", "boss frames", "castbar", "castbars", "cast bar", "cast bars",
    "bar", "bars", "texture", "textures", "color", "colors", "font", "fonts",
    "profile", "profiles", "group", "group frame", "group frames", "party", "party frame",
    "party frames", "raid", "raid frame", "raid frames", "layout", "health text",
    "group text", "indicator", "indicators", "corner indicator", "corner indicators",
    "ready check", "ready checks", "raid marker", "raid markers", "role icon", "role icons",
    "class resource", "class resources", "class power", "gameplay", "status icon",
    "status icons", "module", "modules", "style module", "dropdown style",
    "text slot", "text slots", "copy", "export", "import",
    "combat timer", "combat state", "combat enter", "combat leave",
    "totem frame", "totems", "statue frame", "combat crosshair",
    "crosshair", "target sound", "detached power", "detached power bar", "alternative mana",
    "alt mana", "menu scale", "ui scale", "display recovery", "recovery",
    "spieler", "ziel", "fokus", "begleiter", "gruppe", "gruppenframe", "gruppenframes",
    "profil", "profile", "farben", "farbe", "schrift", "zauberleiste",
}

R.SCOPED_HELP_INTENT_TERMS = {    "help", "help for", "help with", "help me with", "commands for", "show commands for",
    "show me", "show me options", "list", "list options", "explain where",
    "help me find", "help me locate", "can you help me find", "can you help me locate",
    "i want to change", "i want to adjust", "i want to configure", "i want to manage",
    "i need to change", "i need to adjust", "i need to configure", "i need to manage",
    "i am trying to change", "i am trying to adjust", "i am trying to configure", "i am trying to manage",
    "i'm trying to change", "i'm trying to adjust", "i'm trying to configure", "i'm trying to manage",
    "im trying to change", "im trying to adjust", "im trying to configure", "im trying to manage",
    "i am looking for", "i'm looking for", "im looking for", "i need help with",
    "what can i change", "what settings can i change", "what can i do",
    "how do i change", "how can i change", "how do i configure", "how can i configure",
    "how do i adjust", "how can i adjust", "how do i set", "how can i set",
    "where should i go", "where should i go to", "where should i go for",
    "where do i manage", "where can i manage", "where do i edit", "where can i edit",
    "where are", "where can i change", "where do i change", "where can i adjust", "where do i adjust",
    "where can i configure", "where do i configure", "which page has", "which page contains",
    "which menu has", "which menu contains", "what page has", "what menu has",
    "what controls", "what option changes", "what setting controls", "tell me where", "tell me where to",
    "what can i change here", "what can i do here", "how do profiles work",
    "hilfe", "hilfe fuer", "hilfe mit", "befehle fuer", "was kann ich aendern",
    "was kann ich hier aendern", "was kann ich tun", "was kann ich hier tun",
}

function R.LooksLikeConcreteScopedValueRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, {
        "option", "options", "where", "which page", "which menu", "what page", "what menu",
        "help me find", "help me locate", "find options", "locate options",
    }) then
        return false
    end
    if norm:match("%d") or norm:match("#%x%x%x") then return true end
    if R.ContainsAny(norm, {
        "turn on", "turn off", "enable", "disable", "hide", "show",
        "bigger", "smaller", "larger", "wider", "narrower", "taller", "shorter",
        "increase", "decrease", "raise", "lower", "on", "off", "true", "false",
    }) then
        return true
    end
    if R.ContainsAny(norm, R.COLOR_TERMS) and R.ContainsAny(norm, { "set", "change", "make" }) then return true end
    return false
end

function R.LooksLikeScopedHelpKnowledgeRequest(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, { "what did you change", "what changed", "what was changed", "last change", "previous change" }) then return false end
    if R.LooksLikeGuidedTourRequest(norm) then return false end
    if R.ContainsAny(norm, { "open", "go to", "show settings", "show me settings", "oeffne" })
        and not R.ContainsAny(norm, { "where should i go", "where should i go to", "where should i go for" })
    then
        return false
    end
    if R.LooksLikeConcreteScopedValueRequest(norm) then return false end

    local hasIntent = R.ContainsAny(norm, R.SCOPED_HELP_INTENT_TERMS)
    if not hasIntent
        and R.ContainsAny(norm, { "i want", "i need" })
        and R.ContainsAny(norm, { "option", "options", "where", "find", "locate", "page", "menu" })
    then
        hasIntent = true
    end
    return hasIntent and R.ContainsAny(norm, R.SCOPED_HELP_SCOPE_TERMS)
end

function R.BugReportReply(text)    return {
        text = "Thanks for wanting to report it. That would really help MSUF development, especially if I can reproduce it.\nDiscord: " .. R.DISCORD_INVITE .. "\nAlternatively, you can leave a comment on the MSUF CurseForge page: " .. R.CURSEFORGE_PAGE .. "\nHelpful details: the exact Assistant text, the open MSUF page, what you expected, and what actually happened.",
        status = "info",
        summary = "Assistant bug report help",
    }
end

function R.NextConversationJoke()    local jokes = R.WOW_JOKES_EN
    if #jokes == 0 then return nil end

    local key = "lastEnglishJokeIndex"
    local index = 1
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        index = (tonumber(ctx[key]) or 0) + 1
        if index > #jokes then index = 1 end
        ctx[key] = index
    end
    return jokes[index]
end

function R.AssistantCapabilityReply()    local helper = A.Knowledge and A.Knowledge.CapabilityHelp
    if type(helper) == "function" then return helper(false) end
    return {
        text = "I'm the local MSUF Assistant. I can find and explain MSUF options, open pages, run checks, and apply safe changes.",
        status = "info",
        summary = "Assistant capabilities",
    }
end

function A.RouterChatGPTStyleReply()
    return {
        text = "Yes, for MSUF and WoW UI setup. I run locally inside MSUF instead of calling an external ChatGPT service, so I use the addon menu, registry, and current profile state that exist on your client.\nI can answer MSUF questions, find options, open pages, run checks, apply concrete safe changes, and help with undo or redo.\nMy limits: I do not browse live patch data, invent current class or talent guides, or bypass WoW combat restrictions. For live guides I point you to current external resources, and for protected changes I wait until they are safe.",
        status = "info",
        summary = "Assistant ChatGPT-style answer",
    }
end

function A.RouterLimitsReply()
    return {
        text = "MSUF Assistant limits\nI work locally from MSUF's own menu, registry, profile, and diagnostic data. I can help with MSUF UI setup and WoW UI readability, but I do not call an external AI service, browse the web, or know live class/talent tuning.\nI also will not guess destructive profile actions, bypass WoW combat lockdown, or apply vague changes when several MSUF options could match. In those cases I explain the choice, ask for a specific target, or suggest a safe page to open.",
        status = "info",
        summary = "Assistant limits",
    }
end

function R.TroubleshootingReply()    return {
        text = "Troubleshooting help\nI can run local MSUF checks, inspect common visibility problems, build support text, and open recovery tools. Start with 'run checks' or name the broken area, for example: why is target cast bar hidden; why are party frames hidden; why are target buffs hidden.\nYou can ask: Run Checks | Assistant Support Text | Open Display & Recovery",
        status = "info",
        summary = "Assistant troubleshooting help",
    }
end

function R.HumanConversationReply(text)    local norm = R.Normalize(text)
    if norm == "" then return nil end

    if R.ContainsAny(norm, {
        "tell me a joke", "tell joke", "tell me another joke", "another joke", "say something funny", "make me laugh", "joke", "jokes",
        "erzaehl mir einen witz", "erzaehle mir einen witz", "erzaehl einen witz",
        "erzaehle einen witz", "mach einen witz", "noch einen witz", "noch ein witz", "naechster witz", "witz",
    }) then
        return {
            text = R.NextConversationJoke() or "Sure. MSUF is ready for the next joke.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if norm == "help"
        or norm == "help me"
        or norm == "i need help"
        or norm == "show me help"
        or norm == "show help"
        or norm == "hilfe"
        or norm == "hilf mir"
        or norm == "ich brauche hilfe"
        or norm == "brauche hilfe"
        or norm == "zeige mir hilfe"
        or norm == "zeig mir hilfe"
        or norm == "zeige mir alles"
        or norm == "show me everything"
    then
        return R.AssistantCapabilityReply()
    end

    if R.ContainsAny(norm, {
        "what is msuf", "what is midnight simple unit frames", "what are midnight simple unit frames",
        "was ist msuf", "was sind midnight simple unit frames",
    }) then
        return {
            text = "MSUF is Midnight Simple Unit Frames, a local WoW unit-frame addon. I can help with its frames, cast bars, auras, group frames, class resources, gameplay helpers, profiles, and diagnostics. Ask me to find an option, open a page, explain a setting, run checks, or apply a concrete MSUF change.",
            status = "info",
            summary = "MSUF overview",
        }
    end

    if R.ContainsAny(norm, {
        "cant find auras", "can't find auras", "cannot find auras", "where are auras",
        "where do i find auras", "where is auras", "find auras",
        "ich finde auren nicht", "finde auren nicht", "wo sind auren", "wo finde ich auren",
        "auren nicht finden", "auren suche",
    }) then
        return {
            text = "Auras are in the MSUF Auras pages. I can open Aura pages, explain live filters, change icon size/count/growth, adjust cooldown and stack text, list saved legacy hidden-aura data, and run visibility checks. Exact SpellID blacklist edits are read-only in the native 12.1 backend. Ask: open auras; where do I change aura filters; why are target buffs hidden?",
            status = "info",
            summary = "Auras help",
        }
    end

    if R.ContainsAny(norm, {
        "profile import broken", "profile import not working", "import broken", "import not working",
        "import failed", "profile import failed", "import kaputt", "profil import kaputt",
        "profile import kaputt", "import geht nicht", "profil import geht nicht",
    }) then
        return {
            text = "Profile import help\nOpen Profiles first, paste a full MSUF profile string, and import into a backup or new profile when possible. I can open the import panel, export the current profile first, or run a profile check.\nYou can ask: Open Profile Import | Export Current Profile | Check Profiles",
            status = "info",
            summary = "Profile import help",
        }
    end

    if R.ContainsAny(norm, {
        "what are your limits", "what are your limitations", "assistant limits", "assistant limitations",
        "what cant you do", "what can't you do", "what can you not do", "what do you not do",
        "can you do everything", "are you online", "do you use internet", "do you browse",
        "was kannst du nicht", "was kannst du nicht machen", "wo sind deine grenzen",
        "was sind deine grenzen", "bist du online", "hast du internet",
    }) then
        return A.RouterLimitsReply()
    end

    if R.ContainsAny(norm, {
        "what can you do", "what can i ask", "what can i ask you", "what can the assistant do",
        "what can msuf assistant do", "assistant help", "show commands", "what commands",
        "which commands", "available commands", "commands list", "list commands",
        "was kannst du", "was kannst du alles", "was kann der assistant", "was kann der assistent",
        "was kann msuf assistant", "was kann msuf assistent", "was kann ich fragen", "zeig mir befehle",
        "welche befehle", "welche befehle gibt es", "befehle gibt es", "befehle anzeigen",
    }) then
        return R.AssistantCapabilityReply()
    end

    if R.ContainsAny(norm, {
        "chatgpt", "chat gpt", "ai assistant", "ai chat", "like chatgpt", "like chat gpt",
        "be like chatgpt", "talk like chatgpt", "wie chatgpt", "wie chat gpt",
        "how close are you to chatgpt", "close to chatgpt", "chatgpt in game", "chatgpt ingame",
        "ingame chatgpt", "in game chatgpt", "local chatgpt", "ki assistant", "ki assistent",
        "ki chat", "wie eine ki", "wie nah an chatgpt", "wie nahe an chatgpt", "chatgpt ingame",
    }) then
        return A.RouterChatGPTStyleReply()
    end

    if R.ContainsAny(norm, {
        "can we talk", "talk to me", "chat with me", "normal talk", "talk normally", "just talk",
        "small talk", "talk about msuf", "talk about wow", "chat about msuf", "chat about wow",
        "normal reden", "einfach reden", "lass uns reden", "kannst du normal reden",
        "rede ueber msuf", "reden ueber msuf", "ueber msuf reden",
        "rede ueber wow", "reden ueber wow", "ueber wow reden",
    }) then
        return {
            text = "Yes. I work best with MSUF, unit frames, auras, cast bars, profiles, or WoW UI readability. For current class, talent, and patch guides I point to current guides because MSUF runs offline.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if R.ContainsAny(norm, {
        "interface broken", "ui broken", "addon broken", "broken interface", "broken ui",
        "everything is broken", "something is broken", "interface problem", "ui problem",
        "addon problem", "interface issue", "ui issue", "not working", "does not work",
        "doesnt work", "why is my interface broken", "why is my ui broken",
        "interface kaputt", "interface ist kaputt", "mein interface ist kaputt",
        "ui kaputt", "ui ist kaputt", "meine ui ist kaputt", "addon kaputt", "alles kaputt",
        "warum ist mein interface kaputt", "warum ist meine ui kaputt", "funktioniert nicht",
        "geht nicht", "problem mit interface", "problem mit ui", "fehler im interface",
        "unitframes weg", "unit frames weg", "frames weg", "rahmen weg",
        "unit frames gone", "unitframes gone", "unit frames missing", "unitframes missing",
        "unit frames not shown", "unitframes not shown", "unit frames not showing", "unitframes not showing",
        "frames gone", "frames are gone", "my frames are gone", "frames missing", "frames are missing",
        "frames not shown", "frames not showing", "my ui is gone", "everything is gone",
        "settings disappeared", "settings missing", "settings are missing", "options disappeared",
        "party frames weg", "raid frames weg", "group frames weg", "gruppenframes weg",
        "ziel buffs weg", "target buffs gone", "ziel castbar weg", "target castbar gone",
        "spieler frame unsichtbar", "player frame invisible", "frames unsichtbar", "rahmen unsichtbar",
    }) then
        return R.TroubleshootingReply()
    end

    if R.ContainsAny(norm, {
        "get better at wow", "better at wow", "improve at wow", "improve in wow", "wow improvement",
        "learn wow", "wow guide", "guide for wow", "class guide", "rotation guide", "talent guide",
        "best talents", "best build", "dps guide", "healer guide", "tank guide", "raid guide",
        "mythic plus guide", "m plus guide", "m+ guide", "how do i play my class",
        "where can i find wow guides", "wowhead", "help with wow", "wow help",
        "can you help with wow", "can you help me with wow", "help me with wow",
        "besser in wow", "besser bei wow", "wow besser", "wie werde ich besser",
        "wie werde ich besser in wow", "kannst du mit wow helfen", "hilf mir mit wow",
        "hilfe mit wow", "wow hilfe", "klassenguide", "klassen guide", "talente",
        "rotation", "spielweise", "wow guide deutsch",
    }) then
        return {
            text = "For live class, talent, and patch guides, I point to current Wowhead guides because MSUF runs offline. Check Wowhead: " .. R.WOWHEAD_GUIDES .. ". For UI setup, unit frames, visibility, text, and MSUF profiles, I can help directly here.",
            status = "info",
            summary = "General WoW help",
        }
    end

    if R.ContainsAny(norm, { "how are you", "how are you doing", "are you ok", "you good", "wie gehts", "wie geht es dir", "alles gut", "gehts dir gut" }) then
        return {
            text = "I'm ready to help with MSUF. Name the option or frame you want to change, or ask where something is.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if R.ContainsAny(norm, { "hi", "hello", "hey", "good morning", "good evening", "hallo", "moin", "servus" }) then
        return {
            text = "Hi. I'm the local MSUF Assistant. Name what you want to change or find in MSUF.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if R.ContainsAny(norm, { "thanks", "thank you", "thx", "danke", "danke dir" }) then
        return {
            text = "You're welcome. Give me the next MSUF change whenever you're ready.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if R.ContainsAny(norm, { "who are you", "what are you", "wer bist du", "was bist du" }) then
        return {
            text = "I'm the local MSUF Assistant. I can change MSUF options, explain pages, and ask follow-up questions when a request needs a choice. For auras, I change areas that have a matching MSUF option.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    return nil
end

function A.TryImmediateConversationReply(text)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if A.RouterHasBlockingPendingAssistantState and A.RouterHasBlockingPendingAssistantState() then return nil end
    if R.IMMEDIATE_SHORT_CONVERSATION[norm] then
        return R.HumanConversationReply(text)
    end
    for i = 1, #(R.IMMEDIATE_CONVERSATION_PHRASES or {}) do
        if R.HasNormalizedPhrase(norm, R.IMMEDIATE_CONVERSATION_PHRASES[i]) then
            return R.HumanConversationReply(text)
        end
    end
    if R.HasNormalizedPhrase(norm, "help") and #norm <= 20 then
        return R.HumanConversationReply(text)
    end
    if norm == "help me" or norm == "i need help" or norm == "show help" then
        return R.HumanConversationReply(text)
    end
    if R.AsksSettingLocation(norm) and A.RouterLooksLikeVisualSettingTopic
        and A.RouterLooksLikeVisualSettingTopic(norm)
        and A.RouterTryVisualSettingShortcut
    then
        local visualHelp = A.RouterTryVisualSettingShortcut(norm, nil)
        if visualHelp then
            visualHelp.status = "info"
            visualHelp.result = "info"
            return visualHelp
        end
    end
    return nil
end

function R.UnsupportedAuraReply(text)    local norm = R.Normalize(text)
    local parser = A.Parser or {}
    if type(parser.CopyCommandExcludesAuras) == "function" and parser.CopyCommandExcludesAuras(norm) then return nil end
    if R.ContainsAny(norm, { "debuff stripe", "debuff stripes" }) then return nil end
    if R.ContainsAny(norm, { "dispel overlay", "unitframe dispel overlay", "unit frame dispel overlay" }) then return nil end
    if not R.ContainsAny(norm, R.AURA_OUT_OF_SCOPE_TERMS)
        and not (R.ContainsAny(norm, R.AURA_BUFF_TERMS) and R.ContainsAny(norm, R.AURA_BUFF_CONTEXT_TERMS))
    then
        return nil
    end
    return {
        kind = "unsupported",
        status = "info",
        summary = "Aura option fallback.",
        text = "I don't see an MSUF aura option for that request yet. I can change aura icon size, caps/count, X/Y offsets, spacing, growth, layer, cooldown text, stack text, duration bars, live filter tokens, quick presets, private aura options, and group aura copy when those options exist in MSUF. Saved exact SpellID blacklist data can be listed, but it is read-only while the native 12.1 backend is active. Aura areas I can't match will stay as they are.",
    }
end

R.NATURAL_PROBLEM_TERMS = {    "gone", "missing", "disappeared", "vanished", "lost", "not shown", "not showing",
    "not displayed", "not appearing", "does not show", "doesn't show", "cannot see", "can't see", "cant see", "hidden",
    "fix", "repair",
    "weg", "fehlt", "verschwunden", "nicht angezeigt", "wird nicht angezeigt",
    "werden nicht angezeigt", "unsichtbar", "nicht sichtbar", "versteckt", "ausgeblendet",
}

function R.HasNaturalProblemTerm(norm)    return R.ContainsAny(norm, R.NATURAL_PROBLEM_TERMS)
        or (R.ContainsAny(norm, { "sehe", "sehen" }) and R.ContainsAny(norm, { "nicht" }))
end

R.NATURAL_PROFILE_PROBLEM_TERMS = {    "profile", "profiles", "profil", "profile import", "import profile",
}

R.NATURAL_GENERIC_PROBLEM_TOPICS = {    "frame", "frames", "unit frame", "unit frames", "unitframe", "unitframes",
    "ui", "interface", "settings", "setting", "options", "option",
    "everything", "all", "alles",
    "einstellungen", "optionen",
}

R.NATURAL_CONCRETE_VISIBILITY_TOPICS = {    "player", "target", "focus", "pet", "boss", "party", "raid", "mythic raid",
    "spieler", "ziel", "fokus", "begleiter", "gruppe", "schlachtzug",
    "aura", "auras", "auren", "buff", "buffs", "debuff", "debuffs",
    "castbar", "cast bar", "zauberleiste",
    "class resource", "class resources", "class power", "combo point", "combo points",
    "holy power", "alternative mana", "alt mana", "combat timer",
    "totem", "totems", "totem frame", "statue frame", "combat crosshair", "crosshair",
    "target sound", "target sounds",
}

function R.TryNaturalProblemShortcut(text, coreHandler)    local norm = R.Normalize(text)
    if norm == "" or not R.HasNaturalProblemTerm(norm) then return nil end

    if type(coreHandler) == "function" and R.ContainsAny(norm, R.NATURAL_PROFILE_PROBLEM_TERMS) then
        local result = coreHandler("profile missing")
        if result and not (type(result) == "table" and result.kind == "unknown") then return result end
    end

    if R.ContainsAny(norm, R.NATURAL_GENERIC_PROBLEM_TOPICS)
        and not R.ContainsAny(norm, R.NATURAL_CONCRETE_VISIBILITY_TOPICS)
    then
        return R.TroubleshootingReply()
    end

    return nil
end

R.READABILITY_PROBLEM_TERMS = {    "too small", "too tiny", "too big", "too large", "tiny", "unreadable",
    "hard to read", "hard to see", "cannot read", "can't read", "cant read",
    "easier to read", "easier to see", "easier to track", "easier to understand",
    "more readable", "hard to understand", "cleaner", "clean up", "simpler",
    "too busy", "busy", "too noisy", "noisy", "messy", "confusing", "overwhelming",
    "overlap", "overlaps", "overlapping", "crowded", "cluttered",
    "zu klein", "zu gross", "schwer zu lesen", "nicht lesen",
    "kann den text nicht lesen", "ueberlappen", "ueberlappt",
}

R.READABILITY_AURA_TERMS = {    "aura", "auras", "auren", "buff", "buffs", "debuff", "debuffs", "icon", "icons",
}

R.READABILITY_CASTBAR_TERMS = {    "cast", "casts", "boss cast", "boss casts", "castbar", "castbars", "cast bar", "cast bars", "zauberleiste", "zauberleisten",
}

R.READABILITY_GROUP_TERMS = {    "party", "party frame", "party frames", "raid", "raid frame", "raid frames",
    "group frame", "group frames", "gruppe", "gruppenframes", "schlachtzug",
}

R.READABILITY_TEXT_TERMS = {    "text", "font", "name", "names", "hp", "health", "power", "read",
    "lesen", "schrift",
}

R.READABILITY_MENU_TERMS = {    "menu", "dashboard", "options", "config", "assistant", "ui", "interface",
    "everything", "all", "alles",
}

R.READABILITY_FRAME_TERMS = {    "frame", "frames", "unit frame", "unit frames", "unitframe", "unitframes",
    "player", "target", "focus", "boss", "spieler", "ziel", "fokus",
}

function R.ReadabilityReply(title, body, examples, actions, clarification)    A.lastAssistantHelpContext = {
        kind = "readability",
        title = tostring(title or "Readability help"),
        examples = tostring(examples or "set player width to 300; set target cast bar height to 24."),
        actions = tostring(actions or "Open Dashboard Scaling | Open Fonts"),
        clarification = clarification,
    }
    return {
        text = tostring(title or "Readability help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "set player width to 300; set target cast bar height to 24.") .. "\nYou can ask: " .. tostring(actions or "Open Dashboard Scaling | Open Fonts"),
        status = "info",
        summary = "Assistant readability help",
    }
end

R.HELP_CONTEXT_NEXT_TERMS = {    "what should i change first", "what should i do first", "where should i start",
    "what next", "what now", "next step", "next steps", "recommend a first change",
    "recommend first change", "what would you change first",
}

R.HELP_CONTEXT_EXAMPLE_TERMS = {    "show examples", "examples", "example", "give examples", "show me examples",
    "what can i say", "what should i type",
}

R.HELP_CONTEXT_OPEN_TERMS = {    "open it", "open that", "open this", "show it", "show that", "show this",
    "take me there", "go there", "open the page", "open that page",
}

R.HELP_CONTEXT_LOCATION_TERMS = {
    "where is it", "where is that", "where is this", "where are they", "where are those",
    "where do i change it", "where do i change that", "where do i change this", "where do i change them", "where do i change those",
    "where can i change it", "where can i change that", "where can i change this", "where can i change them", "where can i change those",
    "where do i configure it", "where do i configure that", "where do i configure this", "where do i configure them", "where do i configure those",
    "where can i configure it", "where can i configure that", "where can i configure this", "where can i configure them", "where can i configure those",
    "where do i find it", "where do i find that", "where do i find this", "where do i find them", "where do i find those",
    "where can i find it", "where can i find that", "where can i find this", "where can i find them", "where can i find those",
    "which page is it on", "which page is that on", "which page is this on", "which page are they on", "which page are those on",
    "what page is it on", "what page is that on", "what page is this on", "what page are they on", "what page are those on",
    "what menu is it in", "what menu is that in", "what menu is this in", "what menu are they in", "what menu are those in",
}

R.HELP_CONTEXT_PRONOUN_VISIBILITY_TERMS = {
    "show it", "show that", "show this", "show them", "show those",
    "hide it", "hide that", "hide this", "hide them", "hide those",
    "enable it", "enable that", "enable this", "enable them", "enable those",
    "disable it", "disable that", "disable this", "disable them", "disable those",
    "toggle it", "toggle that", "toggle this", "toggle them", "toggle those",
    "turn it on", "turn that on", "turn this on", "turn them on", "turn those on",
    "turn it off", "turn that off", "turn this off", "turn them off", "turn those off",
    "switch it on", "switch that on", "switch this on", "switch them on", "switch those on",
    "switch it off", "switch that off", "switch this off", "switch them off", "switch those off",
}

R.HELP_CONTEXT_PRONOUN_CHANGE_TERMS = {    "make it", "make that", "make this", "change it", "change that", "change this",
    "set it", "set that", "set this", "move it", "move that", "move this",
    "make them", "make those", "change them", "change those",
    "set them", "set those", "move them", "move those",
}

R.HELP_CONTEXT_PRONOUN_TERMS = { "it", "that", "this", "them", "those" }

function R.LooksLikeHelpContextFollowup(norm)    return R.ContainsAny(norm, R.HELP_CONTEXT_OPEN_TERMS)
        or (R.ContainsAny(norm, R.HELP_CONTEXT_LOCATION_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS))
        or R.ContainsAny(norm, R.HELP_CONTEXT_EXAMPLE_TERMS)
        or R.ContainsAny(norm, R.HELP_CONTEXT_NEXT_TERMS)
        or (R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_VISIBILITY_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS))
        or (R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_CHANGE_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS))
end

function R.ClearStaleHelpContextForInput(text)    if type(A.lastAssistantHelpContext) ~= "table" then return end
    local norm = R.Normalize(text)
    if norm == "" or R.LooksLikeHelpContextFollowup(norm) then return end
    A.lastAssistantHelpContext = nil
end

function R.FirstOpenActionCommand(actions)    local first = tostring(actions or ""):match("([^|]+)")
    first = R.Trim(first or "")
    if first == "" then return nil end
    local label = first:match("^[Oo]pen%s+(.+)$")
    if not label or R.Trim(label) == "" then return nil end
    return "open " .. R.Trim(label)
end

function R.TryHelpContextFollowup(text, coreHandler)    local ctx = type(A.lastAssistantHelpContext) == "table" and A.lastAssistantHelpContext or nil
    if not ctx or (ctx.kind ~= "readability" and ctx.kind ~= "knowledge") then return nil end

    local norm = R.Normalize(text)
    if norm == "" then return nil end

    if R.ContainsAny(norm, R.HELP_CONTEXT_LOCATION_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS) then
        local command = R.FirstOpenActionCommand(ctx.actions)
        local label = command and R.Trim(command:gsub("^open%s+", "")) or ""
        local location = label ~= "" and ("This topic is handled from " .. label .. ".") or ("Use the action list for this help topic: " .. tostring(ctx.actions))
        return {
            text = tostring(ctx.title) .. "\n" .. location .. "\nExamples: " .. tostring(ctx.examples) .. "\nYou can ask: " .. tostring(ctx.actions),
            status = "info",
            summary = "Assistant help location",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_VISIBILITY_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS) then
        local clarification = tostring(ctx.clarification or "Name the exact MSUF area before I change it, so I do not guess wrong.")
        return {
            text = tostring(ctx.title) .. "\n" .. clarification .. "\nExamples: " .. tostring(ctx.examples),
            status = "info",
            summary = "Assistant help clarification",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_OPEN_TERMS) then
        local command = R.FirstOpenActionCommand(ctx.actions)
        if command and type(coreHandler) == "function" then
            local result = coreHandler(command)
            if result and not (type(result) == "table" and result.kind == "unknown") then
                if type(result) == "table" and R.Trim(result.text or "") == "" then
                    local label = R.Trim(command:gsub("^open%s+", ""))
                    result.text = label ~= "" and ("Opened " .. label .. ".") or "Opened the matching MSUF page."
                    result.status = result.status or "applied"
                end
                return result
            end
        end
        return {
            text = tostring(ctx.title) .. "\nUse the matching action from this help topic: " .. tostring(ctx.actions),
            status = "info",
            summary = "Assistant help follow-up",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_EXAMPLE_TERMS) then
        return {
            text = tostring(ctx.title) .. "\nExamples: " .. tostring(ctx.examples),
            status = "info",
            summary = "Assistant help examples",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_NEXT_TERMS) then
        local nextStep = tostring(ctx.nextStep or "Start with the least destructive visible setting: open the matching page, adjust size or text first, then tune spacing, filters, or colors only if it is still hard to read.")
        return {
            text = tostring(ctx.title) .. "\n" .. nextStep .. "\nExamples: " .. tostring(ctx.examples) .. "\nYou can ask: " .. tostring(ctx.actions),
            status = "info",
            summary = "Assistant help next step",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_CHANGE_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS) then
        local clarification = tostring(ctx.clarification or "Name the exact MSUF area before I change it, so I do not guess wrong.")
        return {
            text = tostring(ctx.title) .. "\n" .. clarification .. "\nExamples: " .. tostring(ctx.examples),
            status = "info",
            summary = "Assistant help clarification",
        }
    end

    return nil
end

function R.TryReadabilityShortcut(text)    local norm = R.Normalize(text)
    if norm == "" or not R.ContainsAny(norm, R.READABILITY_PROBLEM_TERMS) then return nil end
    if R.ContainsAny(norm, {
        "make my ui cleaner", "make my interface cleaner",
        "clean up my ui", "clean up my interface",
    }) then
        return nil
    end

    if R.ContainsAny(norm, R.READABILITY_AURA_TERMS) then
        return R.ReadabilityReply(
            "Aura readability help",
            "For aura size and overlap, I can change icon size, caps/count, spacing, growth direction, anchors, X/Y offsets, layer, cooldown text, and stack text when the scope is clear.",
            "set target buff icon size to 30; set party aura spacing to 4; make raid buffs grow up.",
            "Open Auras | Check target buffs"
        )
    end

    if R.ContainsAny(norm, R.READABILITY_CASTBAR_TERMS) then
        return R.ReadabilityReply(
            "Cast bar readability help",
            "For cast bars, I can adjust Player, Target, Focus, and Boss cast bar size, text, icon, position, fill direction, and preview settings.",
            "set target cast bar height to 24; make focus cast bar wider; open cast bars.",
            "Open Cast Bars | Check target cast bar"
        )
    end

    if R.ContainsAny(norm, R.READABILITY_GROUP_TERMS) then
        return R.ReadabilityReply(
            "Group frame readability help",
            "For Party, Raid, and Mythic Raid readability, I can adjust group frame scale, layout, spacing, health text, name text, range fade, and aura layout.",
            "set raid scale for 20 players to 90; set party name text size to 13; open group health and text.",
            "Open Group Layout | Open Group Health & Text"
        )
    end

    if R.ContainsAny(norm, R.READABILITY_TEXT_TERMS) then
        return R.ReadabilityReply(
            "Text readability help",
            "For text readability, I can adjust unit-frame name, health, power, level, status, font-size, anchor, slot, offset, and global font settings.",
            "set player name font size to 14; set target hp text left current; open fonts.",
            "Open Fonts | Open Player | Open Target"
        )
    end

    local unit, unitLabel = R.UnitFrameScopeFromText(norm)
    if unit and unitLabel then
        local examples
        if R.ContainsAny(norm, { "too big", "too large", "overwhelming", "crowded", "cluttered" }) then
            examples = "set " .. unit .. " width to 240; set " .. unit .. " height to 34; open " .. unit .. "."
        else
            examples = "set " .. unit .. " width to 280; set " .. unit .. " height to 44; open " .. unit .. "."
        end
        return R.ReadabilityReply(
            unitLabel .. " frame readability help",
            unitLabel .. " readability usually starts with that frame's Width and Height. If only the words are hard to read, use text/font settings instead; use broad scaling only when the entire UI is too small.",
            examples,
            "Open " .. unitLabel .. " | set " .. unit .. " width to 280 | set " .. unit .. " height to 44",
            "I can help tune " .. unitLabel .. ", but I need an exact Width, Height, text-size, or page-open request before changing it."
        )
    end

    if R.ContainsAny(norm, R.READABILITY_MENU_TERMS) or R.ContainsAny(norm, R.READABILITY_FRAME_TERMS) then
        return R.ReadabilityReply(
            "Scaling readability help",
            "For broad readability, start with Dashboard scaling. I can adjust the MSUF menu scale, MSUF frame scale, WoW UI scale, and then refine frame sizes or text.",
            "open dashboard scaling; set MSUF frame scale to 100; set player width to 300.",
            "Open Dashboard Scaling | Open Fonts"
        )
    end

    return nil
end

R.SIGNAL_PROBLEM_INTENT_TERMS = {    "missing", "gone", "hidden", "invisible", "not visible", "not shown", "not showing",
    "not displayed", "does not show", "doesn't show", "cannot see", "can't see", "cant see",
    "hard to see", "hard to read", "hard to track", "unclear",
    "fehlt", "weg", "versteckt", "unsichtbar", "nicht sichtbar", "nicht angezeigt",
    "schwer zu sehen", "schwer zu lesen",
}

R.SIGNAL_FOCUS_KICK_TERMS = {    "focus kick", "focus kick tracker", "focus kick icon",
    "focus interrupt", "focus interrupt tracker", "focus interrupt icon",
}

R.SIGNAL_INTERRUPT_TERMS = {    "interrupt", "interrupts", "interrupt ready", "interrupt-ready",
    "kick", "kicks", "kick ready", "kick-ready",
}

R.SIGNAL_DISPEL_TERMS = {    "dispel", "dispels", "dispellable", "dispellable debuff", "dispellable debuffs",
    "magic debuff", "curse debuff", "poison debuff", "disease debuff",
}

R.SIGNAL_THREAT_TERMS = {    "threat", "aggro", "aggro border", "threat indicator", "threat status",
}

R.SIGNAL_READY_CHECK_TERMS = {    "ready check", "ready checks", "readycheck", "ready-check",
}

R.SIGNAL_RAID_MARKER_TERMS = {    "raid marker", "raid markers", "raid target marker", "raid target markers",
    "target marker", "target markers", "target icon", "target icons", "world marker",
    "moon", "moon icon", "moon marker", "moon symbol", "moon mark",
    "skull", "skull icon", "skull marker", "skull symbol", "skull mark",
    "cross", "cross icon", "cross marker", "cross symbol", "cross mark", "x marker", "x icon", "red x", "red cross",
    "square", "square icon", "square marker", "square symbol", "square mark", "blue square",
    "star", "star icon", "star marker", "star symbol", "star mark", "yellow star",
    "circle", "circle icon", "circle marker", "circle symbol", "circle mark", "orange circle",
    "diamond", "diamond icon", "diamond marker", "diamond symbol", "diamond mark", "purple diamond",
    "triangle", "triangle icon", "triangle marker", "triangle symbol", "triangle mark", "green triangle",
}

function R.SignalProblemReply(title, body, examples, actions)    return {
        text = tostring(title or "MSUF signal visibility help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open cast bars; open group status and indicators.") .. "\nYou can ask: " .. tostring(actions or "Open Cast Bars | Open Group Status & Indicators"),
        status = "info",
        summary = "Assistant signal visibility help",
    }
end

function R.TrySignalProblemShortcut(text)    local norm = R.Normalize(text)
    if norm == "" or not R.ContainsAny(norm, R.SIGNAL_PROBLEM_INTENT_TERMS) then return nil end

    if R.ContainsAny(norm, R.SIGNAL_FOCUS_KICK_TERMS) then
        return R.SignalProblemReply(
            "Focus Kick Tracker visibility help",
            "The Focus Kick Tracker belongs to Cast Bars. If it is missing, first check that the tracker is enabled, then tune its width, height, text size, preview, and X/Y offsets.",
            "show focus kick tracker; make focus kick tracker bigger; move focus kick tracker left 10; open cast bars.",
            "Open Cast Bars | Explain Focus Kick Tracker"
        )
    end

    if R.ContainsAny(norm, R.SIGNAL_INTERRUPT_TERMS) then
        return R.SignalProblemReply(
            "Interrupt visibility help",
            "For interrupts and kicks, MSUF can improve Target, Focus, and Boss cast bars with Interrupt Ready indicators, Focus Kick Tracker, interrupt colors, and interrupt shake.",
            "show kick ready on target; show focus kick tracker; set uninterruptible cast color red; set target cast bar height to 24.",
            "Open Cast Bars | Explain Interrupt Ready"
        )
    end

    if R.ContainsAny(norm, R.SIGNAL_DISPEL_TERMS) then
        return R.SignalProblemReply(
            "Dispel visibility help",
            "For dispels, start with Aura Filters and Group Status & Indicators. MSUF can show dispellable debuffs, debuff type colors, dispel borders, debuff stripes, and group-frame aura visibility.",
            "show only dispellable debuffs; open aura filters; test dispel border; set raid range fade to 40.",
            "Open Aura Filters | Open Group Status & Indicators | Open Group Auras"
        )
    end

    if R.ContainsAny(norm, R.SIGNAL_THREAT_TERMS) then
        return R.SignalProblemReply(
            "Threat and aggro visibility help",
            "For threat or aggro visibility, use Aggro Border, threat/status indicators, group status and indicators, and colors. Party/Raid frames can also show status cues for group members.",
            "turn on aggro border; test aggro border; set aggro border color red; open group status and indicators.",
            "Open Bars | Open Colors | Open Group Status & Indicators"
        )
    end

    if R.ContainsAny(norm, R.SIGNAL_READY_CHECK_TERMS) then
        return R.SignalProblemReply(
            "Ready Check visibility help",
            "Ready Check icons live in Group Status & Indicators for Party, Raid, and Mythic Raid frames. Check visibility first, then tune size, anchor, layer, and offsets.",
            "show raid ready check icon; set party ready check size to 18; move raid ready check icon right 4.",
            "Open Group Status & Indicators"
        )
    end

    if R.ContainsAny(norm, R.SIGNAL_RAID_MARKER_TERMS) then
        return R.SignalProblemReply(
            "Raid Marker visibility help",
            "Raid markers can appear on unit frames and group frames. In MSUF, tune their visibility, size, anchor, layer, and offsets from the relevant unit or Group Status & Indicators area.",
            "show raid marker on target; set raid marker size to 18; move raid marker icon up 4.",
            "Open Target | Open Player | Open Group Status & Indicators"
        )
    end

    return nil
end

R.COLOR_CONTRAST_PROBLEM_TERMS = {    "color is wrong", "colors are wrong", "color looks wrong", "colors look wrong",
    "wrong color", "wrong colors", "ugly color", "ugly colors", "colors are ugly",
    "too dark", "too bright", "too faded", "too transparent", "faded",
    "opacity too low", "opacity too high", "no contrast", "bad contrast", "poor contrast",
    "contrast bad", "contrast is bad", "contrast looks bad",
    "farbe ist falsch", "farben sind falsch", "farben sehen falsch", "falsche farbe",
    "zu dunkel", "zu hell", "kontrast schlecht", "schlechter kontrast",
    "zu transparent",
}

R.COLOR_CONTRAST_AURA_TERMS = {    "aura", "auras", "auren", "buff", "buffs", "debuff", "debuffs", "icon", "icons",
}

R.COLOR_CONTRAST_CASTBAR_TERMS = {    "castbar", "castbars", "cast bar", "cast bars", "zauberleiste", "zauberleisten",
}

R.COLOR_CONTRAST_TEXT_TERMS = {    "text", "font", "name", "names", "hp text", "health text", "power text",
    "schrift", "text kontrast",
}

R.COLOR_CONTRAST_GROUP_TERMS = {    "party", "party frame", "party frames", "raid", "raid frame", "raid frames",
    "group frame", "group frames", "gruppe", "gruppenframes", "schlachtzug",
}

R.COLOR_CONTRAST_FRAME_TERMS = {    "frame", "frames", "unit frame", "unit frames", "unitframe", "unitframes",
    "player", "target", "focus", "boss", "health bar", "power bar", "bar", "bars",
    "spieler", "ziel", "fokus",
}

function R.ColorContrastReply(title, body, examples, actions)    return {
        text = tostring(title or "Color and contrast help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "set player border color blue; set global font color white.") .. "\nYou can ask: " .. tostring(actions or "Open Colors | Open Bars"),
        status = "info",
        summary = "Assistant color and contrast help",
    }
end

function R.TryColorContrastShortcut(text)    local norm = R.Normalize(text)
    if norm == "" or not R.ContainsAny(norm, R.COLOR_CONTRAST_PROBLEM_TERMS) then return nil end

    if R.ContainsAny(norm, R.COLOR_CONTRAST_AURA_TERMS) then
        return R.ColorContrastReply(
            "Aura color and opacity help",
            "For aura readability, I can adjust aura cooldown text colors, stack text, icon sizing, and live filters. Saved exact hidden-aura lists are read-only in the native 12.1 backend. For faded or hard-to-read aura icons, start by naming the scope and lane.",
            "set aura safe timer color to white; set target buff icon size to 30; check target buffs.",
            "Open Auras | Check target buffs"
        )
    end

    if R.ContainsAny(norm, R.COLOR_CONTRAST_CASTBAR_TERMS) then
        return R.ColorContrastReply(
            "Cast bar color help",
            "For cast bars, I can adjust cast text color, background color, border color, cast colors, interrupt feedback, and interrupt-ready indicators.",
            "set cast bar text color white; set target cast bar height to 24; open cast bars.",
            "Open Cast Bars | Check target cast bar"
        )
    end

    if R.ContainsAny(norm, R.COLOR_CONTRAST_TEXT_TERMS) then
        return R.ColorContrastReply(
            "Text contrast help",
            "For text contrast, I can adjust global font color, unit-frame text colors, health text color modes, font sizes, anchors, and text slots.",
            "set global font color white; set target health text color mode class; set player name font size to 14.",
            "Open Fonts | Open Colors"
        )
    end

    if R.ContainsAny(norm, R.COLOR_CONTRAST_GROUP_TERMS) then
        return R.ColorContrastReply(
            "Group frame color and opacity help",
            "For group frames, I can adjust health text, range fade, debuff stripe colors, bar colors, dispel overlays, and aura readability.",
            "set raid range fade to 40; set party debuff stripe color red; open group health and text.",
            "Open Group Health & Text | Open Group Layout"
        )
    end

    if R.ContainsAny(norm, R.COLOR_CONTRAST_FRAME_TERMS) then
        return R.ColorContrastReply(
            "Frame color and opacity help",
            "For frames and bars, I can adjust bar mode, bar texture, border colors, health bar colors, opacity, range fade, and global color settings.",
            "set global bar mode class; set player border color blue; set player width to 300.",
            "Open Colors | Open Bars"
        )
    end

    return R.ColorContrastReply(
        "Color and contrast help",
        "For color or contrast problems, tell me the area first: frame, cast bar, aura, text, group frames, or class colors. I can then point to the exact MSUF options or apply a concrete change.",
        "set global bar mode class; set cast bar text color white; set player border color blue.",
        "Open Colors | Open Bars"
    )
end

R.VISIBILITY_PROBLEM_TERMS = {    "hidden", "missing", "gone", "invisible", "not visible", "not showing",
    "not shown", "not displayed", "not appearing", "does not show", "doesn't show", "cannot see", "can't see", "cant see",
    "not working", "does not work", "doesn't work", "broken", "fix", "repair",
    "weg", "fehlt", "unsichtbar", "nicht sichtbar", "nicht da", "nicht angezeigt",
    "wird nicht angezeigt", "werden nicht angezeigt", "zeigt nicht", "zeigt keine",
    "versteckt", "ausgeblendet", "verschwunden",
}

R.VISIBILITY_AURA_TERMS = {    "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    "auren",
}

R.VISIBILITY_DEBUFF_TERMS = { "debuff", "debuffs" }
R.VISIBILITY_BUFF_TERMS = { "buff", "buffs" }
R.VISIBILITY_CASTBAR_TERMS = { "castbar", "cast bar", "zauberleiste" }
R.VISIBILITY_PARTY_TERMS = { "party", "party frame", "party frames", "party group", "party group frames" }
R.VISIBILITY_RAID_TERMS = { "raid", "raid frame", "raid frames", "raid group", "raid group frames", "schlachtzug" }
R.VISIBILITY_MYTHIC_TERMS = { "mythic raid", "mythicraid", "mythic raid frame", "mythic raid frames" }
R.VISIBILITY_PLAYER_TERMS = { "player", "player frame", "player unitframe", "spieler", "spieler frame", "spieler unitframe", "spieler rahmen", "ich" }
R.VISIBILITY_TARGETTARGET_TERMS = { "targettarget", "target of target", "target of target frame", "ziel des ziels" }
R.VISIBILITY_TARGET_TERMS = { "target", "target frame", "target unitframe", "ziel", "ziel frame", "ziel rahmen" }
R.VISIBILITY_FOCUSTARGET_TERMS = { "focustarget", "focus target", "focus target frame", "fokus ziel" }
R.VISIBILITY_FOCUS_TERMS = { "focus", "focus frame", "focus unitframe", "fokus", "fokus frame", "fokus rahmen" }
R.VISIBILITY_PET_TERMS = { "pet", "pet frame", "pet unitframe", "begleiter", "begleiter frame", "begleiter rahmen" }
R.VISIBILITY_BOSS_TERMS = { "boss", "boss frame", "boss frames", "boss rahmen" }
R.VISIBILITY_CLASSPOWER_TERMS = {    "class resource", "class resources", "class power", "class powers",
    "combo point", "combo points", "holy power", "resource bar", "resource bars",
}

R.VISIBILITY_ALTMANA_TERMS = {    "alternative mana", "alt mana", "secondary mana", "dual resource mana",
}

R.VISIBILITY_GAMEPLAY_FEATURE_TERMS = {    { query = "check combat timer", terms = { "combat timer" } },
    { query = "check totem frame", terms = { "totem", "totems", "totem frame", "statue frame", "statue" } },
    { query = "check combat crosshair", terms = { "combat crosshair", "crosshair" } },
}

R.VISIBILITY_TARGET_SOUND_TERMS = {    "target sound", "target sounds", "target lost sound", "target select sound",
    "target select lost sound", "play sound on target",
}

A.RouterMiscProblemTerms = A.RouterMiscProblemTerms or {
    minimap = { "minimap icon", "minimap button", "msuf minimap icon", "msuf minimap button" },
    tooltip = {
        "tooltip", "tooltips", "unit tooltip", "unit tooltips",
        "unit frame tooltip", "unit frame tooltips", "unitframe tooltip", "unitframe tooltips",
    },
    blizzard = {
        "blizzard frame", "blizzard frames", "blizzard unit frame", "blizzard unit frames",
        "blizzard unitframe", "blizzard unitframes", "default frame", "default frames",
        "standard frame", "standard frames", "wow frame", "wow frames", "original frame", "original frames",
        "blizzard player frame", "blizzard playerframe", "default player frame", "standard player frame",
    },
    blizzardPlayer = { "player frame", "playerframe", "blizzard player frame", "blizzard playerframe" },
    language = { "menu language", "msuf language", "language", "menu locale" },
    welcome = { "welcome message", "startup message", "start message", "login message" },
    version = {
        "version popup", "version pop up", "version message", "version check",
        "peer version check", "update check", "update message",
    },
    menuSnap = {
        "menu edge snap", "edge snap", "menu snap", "menu snapping", "snap menu",
        "snap the menu", "snap window", "window snap",
    },
    keepsShowing = {
        "keeps showing", "keep showing", "keeps appearing", "keep appearing",
        "keeps popping", "keeps popping up", "keeps opening", "shows every login",
        "shows on login", "appears every login", "appears on login", "still showing",
    },
}

A.RouterRunMiscCore = function(coreHandler, query)
    if type(coreHandler) ~= "function" then return nil end
    local result = coreHandler(query)
    if result and not (type(result) == "table" and result.kind == "unknown") then
        result.summary = result.summary or "Matched by a miscellaneous problem shortcut."
        return result
    end
    return nil
end

A.RouterLooksLikeMiscProblemTopic = function(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    local hasVisibilityProblem = R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS)
    if hasVisibilityProblem and (R.ContainsAny(norm, A.RouterMiscProblemTerms.minimap) or R.ContainsAny(norm, A.RouterMiscProblemTerms.tooltip)) then return true end
    if R.ContainsAny(norm, A.RouterMiscProblemTerms.blizzard)
        and R.ContainsAny(norm, {
            "visible", "still visible", "showing", "still showing", "shows", "still shows",
            "not hidden", "not hiding", "does not hide", "doesn't hide", "cannot hide", "can't hide", "cant hide",
        })
    then
        return true
    end
    if R.ContainsAny(norm, A.RouterMiscProblemTerms.language)
        and R.ContainsAny(norm, { "wrong", "unreadable", "confusing", "not right", "bad language", "falsche sprache" })
    then
        return true
    end
    if (R.ContainsAny(norm, A.RouterMiscProblemTerms.welcome) or R.ContainsAny(norm, A.RouterMiscProblemTerms.version))
        and (R.ContainsAny(norm, A.RouterMiscProblemTerms.keepsShowing) or R.ContainsAny(norm, { "annoying", "popup", "pop up", "disable", "turn off", "hide" }))
    then
        return true
    end
    if R.ContainsAny(norm, A.RouterMiscProblemTerms.menuSnap)
        and R.ContainsAny(norm, { "screen", "edge", "snap", "outside", "off screen", "offscreen" })
    then
        return true
    end
    return false
end

A.RouterTryMiscProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if (R.LooksLikeRegistrySettingLocationQuestion and R.LooksLikeRegistrySettingLocationQuestion(norm))
        or (R.LooksLikeRegistrySettingExplainQuestion and R.LooksLikeRegistrySettingExplainQuestion(norm))
    then
        return nil
    end
    local hasVisibilityProblem = R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS)

    if hasVisibilityProblem and R.ContainsAny(norm, A.RouterMiscProblemTerms.minimap) then
        return A.RouterRunMiscCore(coreHandler, "turn on minimap icon")
            or {
                text = "Minimap icon help\nThe MSUF minimap button is controlled in Miscellaneous. Turn on MSUF Minimap Icon if the button is missing.\nExamples: turn on minimap icon; open miscellaneous.\nYou can ask: Open Miscellaneous",
                status = "info",
                summary = "Assistant minimap icon help",
            }
    end

    if hasVisibilityProblem and R.ContainsAny(norm, A.RouterMiscProblemTerms.tooltip) then
        return A.RouterRunMiscCore(coreHandler, "show tooltips always")
            or {
                text = "Tooltip visibility help\nUnit-frame and group-frame tooltips are controlled in Miscellaneous. Set Show Unit Frame Tooltips to always, out of combat, modifier key, or never.\nExamples: show tooltips always; show tooltips only with ALT; open miscellaneous.\nYou can ask: Open Miscellaneous",
                status = "info",
                summary = "Assistant tooltip visibility help",
            }
    end

    if R.ContainsAny(norm, A.RouterMiscProblemTerms.blizzard)
        and R.ContainsAny(norm, {
            "visible", "still visible", "showing", "still showing", "shows", "still shows",
            "not hidden", "not hiding", "does not hide", "doesn't hide", "cannot hide", "can't hide", "cant hide",
        })
    then
        if R.ContainsAny(norm, A.RouterMiscProblemTerms.blizzardPlayer) then
            return A.RouterRunMiscCore(coreHandler, "turn on fully hide blizzard player frame")
        end
        return A.RouterRunMiscCore(coreHandler, "hide blizzard unit frames")
            or {
                text = "Blizzard frame visibility help\nBlizzard unit-frame handling lives in Miscellaneous. Disable Blizzard Unit Frames to hide the default unit frames, and use Fully Hide Blizzard PlayerFrame if the Blizzard PlayerFrame still appears because of resource-bar compatibility.\nExamples: hide blizzard unit frames; turn on fully hide blizzard player frame; open miscellaneous.\nYou can ask: Open Miscellaneous",
                status = "info",
                summary = "Assistant Blizzard frame visibility help",
            }
    end

    if R.ContainsAny(norm, A.RouterMiscProblemTerms.language)
        and R.ContainsAny(norm, { "wrong", "unreadable", "confusing", "not right", "bad language", "falsche sprache" })
        and not R.ContainsAny(norm, { " to ", "german", "deutsch", "english", "englisch", "automatic", "auto", "french", "spanish" })
    then
        return {
            text = "Menu language help\nMenu Language is in Miscellaneous. Tell me the exact language you want, or set it back to Automatic so MSUF follows the WoW client.\nExamples: set menu language to German; set menu language to English; set menu language to Automatic.\nYou can ask: Open Miscellaneous",
            status = "info",
            summary = "Assistant menu language help",
        }
    end

    if R.ContainsAny(norm, A.RouterMiscProblemTerms.welcome)
        and (R.ContainsAny(norm, A.RouterMiscProblemTerms.keepsShowing) or R.ContainsAny(norm, { "annoying", "popup", "pop up", "disable", "turn off", "hide" }))
    then
        return A.RouterRunMiscCore(coreHandler, "turn off welcome message")
    end

    if R.ContainsAny(norm, A.RouterMiscProblemTerms.version)
        and (R.ContainsAny(norm, A.RouterMiscProblemTerms.keepsShowing) or R.ContainsAny(norm, { "annoying", "popup", "pop up", "disable", "turn off", "hide" }))
    then
        return A.RouterRunMiscCore(coreHandler, "turn off version check")
    end

    if R.ContainsAny(norm, A.RouterMiscProblemTerms.menuSnap)
        and R.ContainsAny(norm, { "screen", "edge", "snap", "outside", "off screen", "offscreen" })
        and not R.ContainsAny(norm, { "turn off", "disable", "without", "no snap" })
    then
        return A.RouterRunMiscCore(coreHandler, "turn on menu edge snap")
    end

    return nil
end

A.RouterEditModeProblemTerms = A.RouterEditModeProblemTerms or {
    editMode = { "edit mode", "editmode", "msuf edit mode", "frame edit mode", "move frames mode" },
    moveFrames = {
        "move frames", "move my frames", "drag frames", "drag my frames",
        "frames wont move", "frames won't move", "frames are stuck", "frame is stuck",
        "cannot move frames", "can't move frames", "cant move frames",
        "cannot drag frames", "can't drag frames", "cant drag frames",
    },
    grid = { "grid", "edit mode grid" },
    snap = { "snap", "edit mode snap", "snap to grid" },
    preview = { "preview", "previews", "edit mode preview", "edit mode previews" },
    anchorPicker = { "anchor picker", "anchor selector", "anchor overlay" },
    problem = {
        "not working", "does not work", "doesn't work", "broken", "missing", "not showing",
        "gone", "stuck", "cannot", "can't", "cant", "wont", "won't", "how do i", "how can i",
    },
}

A.RouterEditModeHelpReply = function(title, body, examples)
    return {
        text = tostring(title or "Edit Mode help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "enter MSUF edit mode; open anchor picker; turn on edit mode grid.") .. "\nYou can ask: Enter Edit Mode | Edit Mode Status | Open Edit Mode Anchor Picker",
        status = "info",
        summary = "Assistant Edit Mode help",
    }
end

A.RouterTryEditModeProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    local terms = A.RouterEditModeProblemTerms
    local mentionsEditMode = R.ContainsAny(norm, terms.editMode) or R.ContainsAny(norm, terms.moveFrames)
    if not mentionsEditMode then return nil end
    local hasProblem = R.ContainsAny(norm, terms.problem) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS)
    local asksHowToMove = R.ContainsAny(norm, { "how do i move frames", "how can i move frames", "move frames mode" })
    if not hasProblem and not asksHowToMove then return nil end

    local asksExitStatus = R.ContainsAny(norm, {
        "why can't i exit edit mode", "why cant i exit edit mode", "why can not i exit edit mode",
        "why can't leave edit mode", "why cant leave edit mode", "why can not leave edit mode",
        "cannot exit edit mode", "can't exit edit mode", "cant exit edit mode",
        "cannot leave edit mode", "can't leave edit mode", "cant leave edit mode",
        "edit mode wont exit", "edit mode won't exit", "stuck in edit mode",
    })
    local asksStatus = asksExitStatus or R.ContainsAny(norm, {
        "edit mode status", "am i in edit mode", "is edit mode on", "is edit mode active",
    })
    if asksStatus then
        if type(coreHandler) == "function" then
            local result = coreHandler(asksExitStatus and "why cant i exit edit mode" or "edit mode status")
            if result and not (type(result) == "table" and result.kind == "unknown") then return result end
        end
        local workflow = A.Workflow and A.Workflow.EditMode
        if workflow and type(workflow.StatusText) == "function" then
            return {
                text = workflow.StatusText(asksExitStatus and "why_exit" or nil),
                status = "applied",
                summary = "Assistant Edit Mode status",
            }
        end
    end

    if R.ContainsAny(norm, terms.anchorPicker) and type(coreHandler) == "function" then
        local result = coreHandler("open edit mode anchor picker")
        if result and not (type(result) == "table" and result.kind == "unknown") then return result end
    end

    if R.ContainsAny(norm, terms.preview) and type(coreHandler) == "function" then
        local bossPreview = R.ContainsAny(norm, {
            "boss preview", "boss frame preview", "boss frames preview",
            "boss unit preview", "boss unitframe preview", "boss unit frame preview",
        }) and not R.ContainsAny(norm, {
            "castbar", "cast bar", "castbars", "cast bars", "boss target",
            "target border", "target highlight",
        })
        local result = coreHandler(bossPreview and "show boss frame preview" or "turn on edit mode previews")
        if result and not (type(result) == "table" and result.kind == "unknown") and result.status ~= "failed" then return result end
    end

    if R.ContainsAny(norm, terms.grid) then
        return A.RouterEditModeHelpReply(
            "Edit Mode grid help",
            "The Edit Mode grid is controlled inside MSUF Edit Mode. Enter MSUF Edit Mode first, then turn on the grid or change grid spacing.",
            "enter MSUF edit mode; turn on edit mode grid; set edit mode grid spacing to 24."
        )
    end

    if R.ContainsAny(norm, terms.snap) then
        return A.RouterEditModeHelpReply(
            "Edit Mode snap help",
            "Edit Mode Snap works while MSUF Edit Mode is active. Enter MSUF Edit Mode first, then enable snap or use the anchor picker for exact anchoring.",
            "enter MSUF edit mode; turn on edit mode snap; open anchor picker."
        )
    end

    if asksHowToMove then
        return A.RouterEditModeHelpReply(
            "Edit Mode help",
            "To move frames visually, enter MSUF Edit Mode, drag frames in the overlay, then exit Edit Mode when the layout is done. For exact anchoring, use the anchor picker.",
            "enter MSUF edit mode; open anchor picker; exit edit mode."
        )
    end

    return A.RouterEditModeHelpReply(
        "Edit Mode troubleshooting help",
        "Frame movement depends on MSUF Edit Mode and WoW combat lockdown. Leave combat, enter MSUF Edit Mode, then use previews, grid, snap, or the anchor picker. If the controls are unavailable, open the Dashboard and try Edit Mode from there.",
        "enter MSUF edit mode; edit mode status; open anchor picker; run checks."
    )
end

A.RouterProfileProblemTerms = A.RouterProfileProblemTerms or {
    profile = { "profile", "profiles", "profile string", "import string", "export string" },
    import = {
        "profile import", "import profile", "import a profile", "import string",
        "profile string", "invalid profile", "invalid import", "invalid string",
        "cannot import", "can't import", "cant import", "import not working",
        "profile import help", "import help",
    },
    export = {
        "profile export", "export profile", "export my profile", "export current profile",
        "backup profile", "backup my profile", "share profile", "share my profile",
        "copy profile string", "profile string",
        "profile backup", "profile backup help", "profile export help", "export help",
    },
    wago = {
        "wago", "wago.io", "what is wago", "what's wago", "what are wago profiles", "wago help",
        "wago profile", "wago profiles", "wago backup", "backup on wago",
        "backup profile on wago", "share on wago", "share profile on wago",
        "share msuf profile on wago", "upload to wago", "upload profile to wago", "post on wago",
        "profile hub", "community profiles",
    },
    copy = {
        "copy my profile", "copy current profile", "copy my current profile",
        "duplicate profile", "backup current profile",
    },
    reset = {
        "reset profile", "reset my profile", "reset active profile", "reset current profile",
        "profile reset", "profile defaults", "restore profile defaults",
    },
    delete = {
        "delete profile", "delete a profile", "remove profile", "remove a profile",
        "profile delete", "profile deletion",
    },
    restore = {
        "restore old profile", "restore profile", "recover profile", "deleted my profile",
        "i deleted my profile", "profile deleted", "lost profile", "reset profile by accident",
        "profile reset by accident", "restore old settings", "recover old settings",
    },
    spec = {
        "spec profile", "specialization profile", "profile switch", "profile switching",
        "profile changed by itself", "profile changed after switching spec",
        "profile changed when switching spec", "changed after switching spec",
        "changed when switching spec", "wrong profile", "profile is wrong", "profile auto switch",
    },
    settingsLost = {
        "settings are gone after reload", "settings gone after reload", "settings disappeared after reload",
        "lost my settings after reload", "my settings are gone after reload",
        "frames reset after relog", "settings reset after relog", "layout reset after relog",
        "frames reset after reload", "settings reset after reload", "layout reset after reload",
    },
}

A.RouterProfileReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Profile help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "show profile summary; export current profile; open profile import.") .. "\nYou can ask: " .. tostring(actions or "Open Profiles | Check Profiles | Export Current Profile"),
        status = "info",
        summary = "Assistant profile help",
    }
end

A.RouterTryProfileProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    local terms = A.RouterProfileProblemTerms
    local mentionsWago = R.ContainsAny(norm, terms.wago)
    local mentionsProfile = mentionsWago or R.ContainsAny(norm, terms.profile) or R.ContainsAny(norm, terms.settingsLost)
    if not mentionsProfile then return nil end
    local asksProfileInfo = R.AsksSettingLocation(norm)
        or norm:match("^can%s+i%s+") ~= nil
        or norm:match("^should%s+i%s+") ~= nil
        or norm:match("^is%s+it%s+safe") ~= nil
        or R.ContainsAny(norm, { "is it safe to", "what happens if", "what does", "what is", "explain" })

    if R.ContainsAny(norm, {
        "which page", "which menu", "where is", "where are", "where can", "where do",
        "tell me where", "explain where", "help me find", "i am looking for",
        "i need help with", "i want", "options",
    })
        and R.ContainsAny(norm, { "profile export" })
        and not R.ContainsAny(norm, { "profile export help", "profile backup help", "export my profile", "how do i", "how can i" })
    then
        return nil
    end

    if mentionsWago and (asksProfileInfo
        or R.ContainsAny(norm, {
            "wago help", "why wago", "wago backup", "backup on wago",
            "backup profile on wago", "share on wago", "share profile on wago",
            "share msuf profile on wago", "upload to wago", "upload profile to wago", "post on wago",
            "how to use wago", "how do i use wago", "how can i use wago",
            "what do i do with wago", "what am i supposed to do",
        }))
    then
        local reply = A.RouterProfileReply(
            "Wago profile sharing help",
            "Wago is a community website many WoW players use to find, share, and store addon import strings. For MSUF, export your current profile first, copy the MSUF profile string, then paste that string into Wago if you want an off-game backup or want to share the layout with someone else. MSUF can create the export string and copy the Wago profiles link, but it does not upload to Wago automatically or manage a Wago account.",
            "export current profile; copy Wago profiles link; open profiles.",
            "Export Current Profile | Copy Wago Profiles Link | Open Profiles"
        )
        reply.searchResults = R.PageFollowupResults("profiles", "Profiles", "Use Profiles export before sharing or backing up an MSUF profile on Wago.")
        return reply
    end

    if R.ContainsAny(norm, terms.restore) then
        return A.RouterProfileReply(
            "Profile recovery help",
            "MSUF can switch to an existing copied profile or import a saved profile string, but it cannot recreate a deleted profile unless you have a backup profile or export string. Do not reset the active profile when you are trying to recover old settings.",
            "show profile summary; switch profile to Backup; import profile string; open profiles.",
            "Check Profiles | Open Profiles | Open Profile Import"
        )
    end

    if R.ContainsAny(norm, terms.reset) and asksProfileInfo then
        return A.RouterProfileReply(
            "Profile reset help",
            "Reset Active Profile lives in Profiles and is confirmation-gated because it can replace many active profile settings. Use export or copy first if you may want to return to the current layout.",
            "open profiles; export current profile; reset active profile.",
            "Open Profiles | Export Current Profile | Check Profiles"
        )
    end

    if R.ContainsAny(norm, terms.delete) and asksProfileInfo then
        return A.RouterProfileReply(
            "Profile delete help",
            "Profile deletion is managed from Profiles and needs an exact profile name plus confirmation. I do not guess which profile to delete from a question.",
            "open profiles; show profile summary; delete profile Raid Backup.",
            "Open Profiles | Check Profiles"
        )
    end

    if R.ContainsAny(norm, terms.import)
        and (asksProfileInfo or R.ContainsAny(norm, { "invalid", "not working", "cannot", "can't", "cant", "help", "how do i", "how can i" }))
    then
        return A.RouterProfileReply(
            "Profile import help",
            "Profile import needs a full MSUF profile string. Open Profiles or the import panel, paste the complete string, and import into a backup or new profile when possible. If MSUF says the string is invalid, ask the sender for a fresh export.",
            "open profile import; import profile into new profile Raid Backup; export current profile first.",
            "Open Profile Import | Export Current Profile | Check Profiles"
        )
    end

    if R.ContainsAny(norm, terms.export)
        and R.ContainsAny(norm, { "help", "how do i", "how can i", "backup", "share", "export" })
    then
        if type(coreHandler) == "function" and R.ContainsAny(norm, { "export my profile", "export current profile" }) then
            local result = coreHandler("export current profile")
            if result and not (type(result) == "table" and result.kind == "unknown") and (result.status or result.result) ~= "failed" then return result end
        end
        local reply = A.RouterProfileReply(
            "Profile backup and export help",
            "Use Profiles export to create a copyable MSUF profile string before risky changes or imports. If export is not available from this context, open Profiles first, then export the current profile.",
            "open profiles; export current profile; copy current profile to Raid Backup.",
            "Open Profiles | Export Current Profile | Check Profiles"
        )
        reply.searchResults = R.PageFollowupResults("profiles", "Profiles", "Profile export and backup controls live on Profiles.")
        return reply
    end

    if R.ContainsAny(norm, terms.copy) and not R.ContainsAny(norm, { " to ", " as ", " called ", " named " }) then
        return A.RouterProfileReply(
            "Profile copy help",
            "Copying the current profile needs a destination profile name, so I do not guess it. Name the backup you want me to create.",
            "copy current profile to Raid Backup; duplicate current profile as Arena Backup; show profile summary.",
            "Open Profiles | Check Profiles"
        )
    end

    if R.ContainsAny(norm, terms.spec) then
        return A.RouterProfileReply(
            "Specialization profile help",
            "If the profile changes by itself, check Auto-switch Profile by Specialization and the specialization profile assignments on Profiles. Turn auto-switch off if you want one profile to stay active across specs.",
            "show profile summary; turn off profile auto switch; set spec profile Frost to Raid; open profiles.",
            "Check Profiles | Open Profiles"
        )
    end

    if R.ContainsAny(norm, terms.settingsLost) then
        return A.RouterProfileReply(
            "Profile storage help",
            "If settings look gone after reload, first check the active profile and saved profiles. You may be on a different profile or specialization auto-switch may have selected another profile.",
            "show profile summary; check profiles; open profiles; turn off profile auto switch.",
            "Check Profiles | Open Profiles | Run Checks"
        )
    end

    if R.HasNaturalProblemTerm(norm) and type(coreHandler) == "function" then
        local result = coreHandler("profile missing")
        if result and not (type(result) == "table" and result.kind == "unknown") then return result end
    end

    return nil
end

A.RouterGroupLayoutProblemTerms = A.RouterGroupLayoutProblemTerms or {
    group = {
        "party frame", "party frames", "raid frame", "raid frames", "mythic raid frame", "mythic raid frames",
        "group frame", "group frames", "party", "raid", "mythic raid",
    },
    sorting = {
        "wrong order", "order is wrong", "sorted wrong", "sorting is wrong", "sort is wrong",
        "role order", "role sorting", "raid groups are wrong", "groups are wrong", "preserve raid groups",
    },
    columns = {
        "one column", "single column", "more columns", "need more columns", "too many columns",
        "columns", "max columns", "units per column",
    },
    spacing = {
        "too far apart", "too close", "spacing is wrong", "spacing wrong", "overlap", "overlaps",
        "overlapping", "crowded", "spread out", "too spread out",
    },
    growth = {
        "grow the wrong way", "growth is wrong", "grow sideways", "grow down", "grow up",
        "growth direction", "fill direction",
    },
    clickCasting = {
        "click casting", "click-casting", "clickcast", "click cast", "mouseover healing",
        "mouse over healing", "not clickable", "cannot click", "can't click", "cant click",
    },
    rangeFade = {
        "range fade", "too faded", "faded out", "out of range", "not fading", "fading out",
    },
    blizzardFallback = {
        "blizzard party frames", "blizzard raid frames", "blizzard group frames",
        "default party frames", "default raid frames", "standard party frames", "standard raid frames",
        "show instead", "showing instead", "fallback", "blizzard fallback",
    },
}

A.RouterGroupLayoutReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Group Layout help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open group layout; set raid max columns to 5; set party growth direction to down.") .. "\nYou can ask: " .. tostring(actions or "Open Group Layout | Open Group Health & Text"),
        status = "info",
        summary = "Assistant group layout help",
    }
end

function R.AsksSettingLocation(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    return norm:match("^where%s+") ~= nil
        or norm:match("^which%s+page") ~= nil
        or norm:match("^what%s+page") ~= nil
        or norm:match("^which%s+menu") ~= nil
        or norm:match("^what%s+menu") ~= nil
        or norm:match("^which%s+setting") ~= nil
        or norm:match("^what%s+setting") ~= nil
        or norm:match("^which%s+option") ~= nil
        or norm:match("^what%s+option") ~= nil
        or norm:match("^what%s+controls") ~= nil
        or norm:match("^which%s+controls") ~= nil
        or norm:match("^how%s+do%s+i") ~= nil
        or norm:match("^how%s+can%s+i") ~= nil
        or norm:match("^can%s+i") ~= nil
        or norm:match("^is%s+there%s+a%s+way") ~= nil
        or R.ContainsAny(norm, { "help me find", "help me locate", "tell me where", "looking for", "show me", "options", "list options", "setting controls", "option controls" })
end

function R.IsDisplayOnlySettingsRequest(norm)
    return R.ContainsAny(norm, { "show me", "show options", "show me options", "list", "list options", "options" })
end

function R.WantsVisibilityOff(norm)
    return R.ContainsAny(norm, { "turn off", "disable", "hide", "remove", "get rid", "dont show", "do not show" })
end

function R.StartsWithVisibilityMutation(norm)
    norm = R.Normalize(norm)
    return norm:match("^turn%s+off%s+") ~= nil
        or norm:match("^hide%s+") ~= nil
        or norm:match("^disable%s+") ~= nil
        or norm:match("^remove%s+") ~= nil
        or norm:match("^get%s+rid%s+of%s+") ~= nil
        or norm:match("^dont%s+show%s+") ~= nil
        or norm:match("^do%s+not%s+show%s+") ~= nil
        or norm:match("^verstecke%s+") ~= nil
        or norm:match("^verstecken%s+") ~= nil
        or norm:match("^ausblenden%s+") ~= nil
        or norm:match("^deaktiviere%s+") ~= nil
        or norm:match("^deaktivieren%s+") ~= nil
        or norm:match("^ausschalten%s+") ~= nil
end

function R.WantsVisibilityOn(norm)
    return R.ContainsAny(norm, { "turn on", "enable", "show", "display" })
end

function R.VisualSettingScope(norm)
    local groupScope, groupLabel = R.GroupScopeFromText(norm)
    if groupScope then return "group", groupScope, groupLabel end
    local unit, unitLabel = R.UnitScopeFromText(norm)
    if unit then return "unit", unit, unitLabel end
    return nil, nil, nil
end

function R.VisualSettingReply(title, body, examples, actions)
    return {
        text = tostring(title or "Visual setting location") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open colors; open bars.") .. "\nYou can ask: " .. tostring(actions or "Open Colors | Open Bars"),
        status = "applied",
        result = "applied",
        summary = "Assistant visual setting help",
    }
end

function A.RouterLooksLikeVisualSettingTopic(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, {
        "health color", "health bar color", "hp color", "health color scheme",
        "health color mode", "class colored", "class coloured", "class color health",
        "opacity", "alpha", "transparent", "transparency", "texture", "textures",
        "bar texture", "health bar texture",
        "range fade", "heal prediction", "incoming heal", "absorb", "absorb overlay",
        "aggro border", "threat border", "border color", "background color", "global font color",
    }) then
        return true
    end
    return false
end

A.RouterTryVisualSettingShortcut = function(norm, coreHandler)
    norm = R.Normalize(norm)
    if norm == "" then return nil end

    local asksLocation = R.AsksSettingLocation(norm)
    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm)
    local scopeKind, scope, scopeLabel = R.VisualSettingScope(norm)
    local hasCore = type(coreHandler) == "function"

    local mentionsHealthColor = R.ContainsAny(norm, {
        "health color", "health bar color", "hp color", "health color scheme",
        "health color mode", "class colored", "class coloured", "class color health",
    })
    local wantsClassHealth = mentionsHealthColor and R.ContainsAny(norm, {
        "class", "class color", "class colored", "class coloured", "by class",
    })
    if mentionsHealthColor then
        if asksLocation then
            if scopeKind == "group" then
                return R.VisualSettingReply(
                    scopeLabel .. " Health Color Mode setting location",
                    scopeLabel .. " Health Color Mode lives in Group Health & Text. Use that when Party, Raid, or Mythic Raid health bars should follow class colors, a custom color, dark mode, or another group health color mode.",
                    "open group health and text; set " .. scope .. " health color mode to class; set " .. scope .. " custom health color green.",
                    "Open Group Health & Text | set " .. scope .. " health color mode to class"
                )
            end
            if scopeKind == "unit" then
                return R.VisualSettingReply(
                    scopeLabel .. " Health Color Scheme setting location",
                    scopeLabel .. " Health Color Scheme lives on the " .. scopeLabel .. " frame page. Use it for class-colored, gradient, unified, dark, or global health-bar coloring for that unit frame.",
                    "open " .. scope .. "; set " .. scope .. " health color scheme to class; set " .. scope .. " health color scheme to global.",
                    "Open " .. scopeLabel .. " | set " .. scope .. " health color scheme to class"
                )
            end
            return R.VisualSettingReply(
                "Health color setting location",
                "Unit-frame health color schemes live on each unit-frame page. Group-frame health color modes live in Group Health & Text. Global palette and bar colors live in Colors.",
                "set player health color scheme to class; set raid health color mode to class; open colors.",
                "Open Player | Open Group Health & Text | Open Colors"
            )
        end
        if wantsClassHealth and scopeKind == "unit" and hasCore then
            return R.CoreControl(
                coreHandler,
                "set " .. scope .. " health color scheme to class",
                scopeLabel .. " Health Color Scheme lives on the " .. scopeLabel .. " page.",
                "info"
            )
        end
        if wantsClassHealth and scopeKind == "group" and hasCore then
            return R.CoreControl(
                coreHandler,
                "set " .. scope .. " health color mode to class",
                scopeLabel .. " Health Color Mode lives in Group Health & Text.",
                "info"
            )
        end
    end

    local mentionsOpacity = R.ContainsAny(norm, { "opacity", "alpha", "transparent", "transparency", "opaque" })
        and not R.ContainsAny(norm, {
            "text opacity", "font opacity", "range fade", "absorb", "heal absorb",
            "dispel overlay", "debuff overlay", "corner indicator",
        })
    if mentionsOpacity and asksLocation then
        if scopeKind == "group" then
            return R.VisualSettingReply(
                scopeLabel .. " Opacity setting location",
                scopeLabel .. " frame opacity lives in Group Health & Text. Use " .. scopeLabel .. " Health Bar Opacity for the filled health bar and " .. scopeLabel .. " Bar Background Opacity for the track/background.",
                "open group health and text; set " .. scope .. " health bar opacity to 80; set " .. scope .. " bar background opacity to 70.",
                "Open Group Health & Text | set " .. scope .. " health bar opacity to 80"
            )
        end
        if scopeKind == "unit" then
            return R.VisualSettingReply(
                scopeLabel .. " Opacity setting location",
                scopeLabel .. " opacity lives on the " .. scopeLabel .. " frame page. Use " .. scopeLabel .. " HP Bar Opacity for the filled health bar and " .. scopeLabel .. " Background Opacity for the track/background.",
                "open " .. scope .. "; set " .. scope .. " hp bar opacity to 80; set " .. scope .. " background opacity to 70.",
                "Open " .. scopeLabel .. " | set " .. scope .. " hp bar opacity to 80"
            )
        end
    end

    local mentionsRangeFade = R.ContainsAny(norm, { "range fade", "out of range", "faded out", "too faded", "fading" })
    if mentionsRangeFade and asksLocation then
        if scopeKind == "group" then
            return R.VisualSettingReply(
                scopeLabel .. " Range Fade setting location",
                scopeLabel .. " Range Fade lives in Group Health & Text. Use " .. scopeLabel .. " Range Fade to enable the behavior, and " .. scopeLabel .. " Range Fade Alpha/Opacity to control how faded out-of-range units become.",
                "open group health and text; turn on " .. scope .. " range fade; set " .. scope .. " range fade alpha to 40.",
                "Open Group Health & Text | turn on " .. scope .. " range fade"
            )
        end
        if scopeKind == "unit" and scope ~= "player" then
            return R.VisualSettingReply(
                scopeLabel .. " Range Fade setting location",
                scopeLabel .. " Range Fade lives on the " .. scopeLabel .. " frame page. Use " .. scopeLabel .. " Range Fade to enable it, and " .. scopeLabel .. " Range Fade Opacity to control out-of-range fading.",
                "open " .. scope .. "; turn on " .. scope .. " range fade; set " .. scope .. " range fade opacity to 40.",
                "Open " .. scopeLabel .. " | turn on " .. scope .. " range fade"
            )
        end
    end

    if R.ContainsAny(norm, { "bar texture", "health bar texture", "power bar texture", "texture" })
        and R.ContainsAny(norm, { "bar", "bars", "health", "power", "texture" })
        and asksLocation
    then
        local label = scopeLabel and (scopeLabel .. " Bar Texture") or "Global Bar Texture"
        local scopeBody = scopeLabel and (label .. " lives in Bars when scoped bar overrides are exposed. Without a scope, use Global Bar Texture for the shared MSUF bar texture.")
            or "Global Bar Texture lives in Bars. Use it for the shared MSUF bar texture, or name a frame/group scope when you want a scoped texture override."
        return R.VisualSettingReply(
            label .. " setting location",
            scopeBody,
            "open bars; set global bar texture to Blizzard; set " .. tostring(scope or "target") .. " bar texture to Blizzard.",
            "Open Bars | set global bar texture to Blizzard"
        )
    end

    if R.ContainsAny(norm, { "heal prediction", "incoming heal prediction", "incoming heal overlay" }) and asksLocation then
        local label = scopeLabel and (scopeLabel .. " Heal Prediction Overlay") or "Heal Prediction Overlay"
        local page = scopeKind == "group" and "Group Health & Text and Bars" or "Bars"
        return R.VisualSettingReply(
            label .. " setting location",
            label .. " is controlled through " .. page .. ". Group scopes can use scoped Heal Prediction Overlay options; the shared overlay controls live in Bars.",
            "open bars; turn off heal prediction overlay; set " .. tostring(scope or "raid") .. " heal prediction anchor to right.",
            "Open Bars | turn off heal prediction overlay"
        )
    end

    if R.ContainsAny(norm, { "absorb", "absorbs", "absorb overlay", "absorb bar", "shield overlay" }) and asksLocation then
        local label = scopeLabel and (scopeLabel .. " Absorb Display Mode") or "Absorb Display Mode"
        return R.VisualSettingReply(
            label .. " setting location",
            label .. " lives in Bars. Use Absorb Display Mode to show absorbs as a bar, overlay/text mode where available, or off. Absorb Bar Opacity, texture, and color are separate Bars/Colors options.",
            "open bars; turn off absorb bar; set absorb bar opacity to 60; set absorb bar color blue.",
            "Open Bars | turn off absorb bar"
        )
    end

    if R.ContainsAny(norm, { "aggro border", "threat border", "aggro outline", "aggro role filter", "aggro shows for" }) and (asksLocation or wantsOff or wantsOn) then
        if asksLocation then
            return R.VisualSettingReply(
                "Aggro Border setting location",
                "Aggro Border and Aggro Shows For live in Bars under Highlight Borders. Its color lives in Colors as Aggro Border Color, and scoped bar overrides can exist for individual frame groups.",
                "open bars; turn off aggro border; set raid aggro shows for non tanks; set aggro border color red.",
                "Open Bars | turn off aggro border"
            )
        end
        if hasCore then
            return R.CoreControl(coreHandler, (wantsOff and "turn off " or "turn on ") .. "aggro border", "Aggro Border lives in Bars.", "info")
        end
    end

    if (R.ContainsAny(norm, { "border color", "frame border color" })
            or (R.ContainsAny(norm, { "border", "outline" }) and R.ContainsAny(norm, R.COLOR_TERMS)))
        and scopeKind == "unit"
        and not R.ContainsAny(norm, { "castbar", "cast bar", "portrait", "power bar", "power border" })
    then
        local reply = R.VisualSettingReply(
            scopeLabel .. " border color help",
            "MSUF does not expose a simple per-" .. scopeLabel .. " frame border color setting. For a unit frame, use " .. scopeLabel .. " Health Color Scheme for health coloring, Portrait Border settings for portraits, Power Bar Border settings for the power bar, or global highlight border colors in Colors/Bars.",
            "open " .. scope .. "; set " .. scope .. " health color scheme to class; set aggro border color red.",
            "Open " .. scopeLabel .. " | Open Colors | Open Bars"
        )
        if not asksLocation then
            reply.status = "info"
            reply.result = "info"
        end
        return reply
    end

    if R.ContainsAny(norm, { "background color", "frame background color", "backdrop color" }) and scopeKind == "unit" and asksLocation then
        return R.VisualSettingReply(
            scopeLabel .. " background color help",
            "MSUF exposes " .. scopeLabel .. " Background Opacity for the unit-frame track/background, while shared bar background colors live in Colors. Use Background Opacity when the frame is too transparent; use Colors for shared bar/background color behavior.",
            "open " .. scope .. "; set " .. scope .. " background opacity to 70; open colors.",
            "Open " .. scopeLabel .. " | Open Colors"
        )
    end

    if R.ContainsAny(norm, { "health text", "hp text", "power text", "mana text", "name text", "font color", "text color" })
        and (R.ContainsAny(norm, R.COLOR_TERMS) or R.ContainsAny(norm, { "color", "colour", "class colored", "class coloured" }))
        and asksLocation
    then
        local label = scopeLabel and (scopeLabel .. " Text Color") or "Text Color"
        local settingLabel = scopeLabel and (scopeLabel .. " Health Text Color Mode") or "Health Text Color Mode"
        return R.VisualSettingReply(
            label .. " setting location",
            settingLabel .. " lives in Fonts and the relevant frame text settings. Literal shared font colors such as white are controlled by Global Font Color in Colors/Fonts; health/power text color modes decide whether text follows health or resource coloring.",
            "open fonts; open colors; set global font color white; set " .. tostring(scope or "target") .. " health text color mode health.",
            "Open Fonts | Open Colors | set global font color white"
        )
    end

    if R.ContainsAny(norm, { "global font color", "font color", "text color" })
        and R.ContainsAny(norm, { "global", "font", "text" })
        and asksLocation
    then
        return R.VisualSettingReply(
            "Global Font Color setting location",
            "Global Font Color lives in Colors/Fonts. Scoped text color behavior, such as Health Text Color Mode or Power Text Color Mode, lives on Fonts and the relevant frame text settings.",
            "open colors; set global font color white; set target health text color mode health.",
            "Open Colors | Open Fonts | set global font color white"
        )
    end

    return nil
end

function R.GroupScopeFromText(norm)
    if R.ContainsAny(norm, { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid" }) then
        return "mythicraid", "Mythic Raid"
    end
    if R.ContainsAny(norm, { "raid", "raid frame", "raid frames" }) then return "raid", "Raid" end
    if R.ContainsAny(norm, { "party", "party frame", "party frames", "group", "group frame", "group frames" }) then return "party", "Party" end
    return nil, nil
end

function R.UnitScopeFromText(norm)
    if R.ContainsAny(norm, { "player", "player frame", "my frame" }) then return "player", "Player" end
    if R.ContainsAny(norm, { "target of target", "targettarget" }) then return "targettarget", "Target of Target" end
    if R.ContainsAny(norm, { "focus target", "focustarget" }) then return "focustarget", "Focus Target" end
    if R.ContainsAny(norm, { "target", "target frame" }) then return "target", "Target" end
    if R.ContainsAny(norm, { "focus", "focus frame" }) then return "focus", "Focus" end
    if R.ContainsAny(norm, { "pet", "pet frame" }) then return "pet", "Pet" end
    if R.ContainsAny(norm, { "boss", "boss frame", "boss frames" }) then return "boss", "Boss" end
    return nil, nil
end

function R.UnitFrameScopeFromText(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, { "target of target frame", "target of target", "targettarget" }) then return "targettarget", "Target of Target" end
    if R.ContainsAny(norm, { "focus target frame", "focus target", "focustarget" }) then return "focustarget", "Focus Target" end
    if R.ContainsAny(norm, { "player frame", "my frame" }) then return "player", "Player" end
    if R.ContainsAny(norm, { "target frame" }) then return "target", "Target" end
    if R.ContainsAny(norm, { "focus frame" }) then return "focus", "Focus" end
    if R.ContainsAny(norm, { "pet frame" }) then return "pet", "Pet" end
    if R.ContainsAny(norm, { "boss frame", "boss frames" }) then return "boss", "Boss" end
    return R.UnitScopeFromText(norm)
end

R.UNIT_FRAME_MOVEMENT_TERMS = {
    "move", "moved", "moving", "movable", "drag", "dragged", "dragging", "position", "place", "placement", "x position", "y position",
    "x offset", "y offset", "offset", "anchor", "anchor to", "anchor point",
    "custom anchor", "custom anchor frame", "reset position", "reset frame position",
    "default position", "lock frames", "unlock frames", "frame lock",
}

R.UNIT_FRAME_MOVEMENT_PROBLEM_TERMS = {
    "not moving", "does not move", "doesn't move", "cannot move", "can't move", "cant move",
    "cannot drag", "can't drag", "cant drag", "wrong position", "position is wrong",
    "wrong place", "anchor is wrong", "offset is wrong", "offset wrong", "stuck",
    "off screen", "offscreen",
}

R.UNIT_FRAME_MOVEMENT_CAPABILITY_TERMS = {
    "can you move", "could you move", "can you drag", "could you drag",
    "can i move", "could i move", "can i drag", "could i drag",
    "can this be moved", "can these be moved", "can the frame be moved", "can frames be moved",
    "can this be dragged", "can these be dragged", "can the frame be dragged", "can frames be dragged",
    "is there a way to move", "is there a way to drag",
    "is it possible to move", "is it possible to drag",
}

R.UNIT_FRAME_MOVEMENT_EXCLUDED_TOPICS = {
    "aura", "auras", "buff", "buffs", "debuff", "debuffs", "castbar", "cast bar",
    "power bar", "power text", "health bar", "health text", "name text",
    "class resource", "class resources", "class power", "combo point", "combo points",
    "holy power", "soul shard", "soul shards", "rune", "runes", "totem",
    "combat timer", "combat crosshair",
}

function R.MovementSettingReply(title, body, examples, actions, status)
    return {
        text = tostring(title or "Frame position setting location") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "enter MSUF edit mode; open player; move player frame down 10.") .. "\nYou can ask: " .. tostring(actions or "Enter Edit Mode | Open Player | Open Target"),
        status = status or "applied",
        result = status or "applied",
        summary = "Assistant frame movement help",
    }
end

function R.LooksLikeFrameCombatMovementQuestion(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    if R.ContainsAny(norm, { "combat timer", "combat crosshair" })
        and not R.ContainsAny(norm, { "in combat", "during combat", "combat lockdown", "lockdown", "protected action", "protected ui" })
    then
        return false
    end
    if not R.ContainsAny(norm, { "combat", "in combat", "during combat", "fight", "fighting", "lockdown", "protected action", "protected ui" }) then
        return false
    end
    if not R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_TERMS)
        and not R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_PROBLEM_TERMS)
        and not R.ContainsAny(norm, { "edit mode", "editmode", "layout", "frame", "frames" })
    then
        return false
    end
    return R.ContainsAny(norm, { "frame", "frames", "unit frame", "unit frames", "edit mode", "editmode", "layout", "anchor", "position", "drag", "move" })
end

function R.LooksLikeMovementCapabilityQuestion(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    if R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_EXCLUDED_TOPICS) then return false end
    if not R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_TERMS) then return false end
    return R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_CAPABILITY_TERMS)
        or norm:match("^can%s+you%s+") ~= nil
        or norm:match("^could%s+you%s+") ~= nil
        or norm:match("^can%s+i%s+") ~= nil
        or norm:match("^could%s+i%s+") ~= nil
        or norm:match("^can%s+.+%s+be%s+moved") ~= nil
        or norm:match("^could%s+.+%s+be%s+moved") ~= nil
        or norm:match("^can%s+.+%s+be%s+dragged") ~= nil
        or norm:match("^could%s+.+%s+be%s+dragged") ~= nil
        or norm:match("^is%s+there%s+a%s+way") ~= nil
        or norm:match("^is%s+it%s+possible") ~= nil
end

function R.HasConcreteMovementChangeDetail(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    if norm:match("[-+]?%d+%.?%d*") then return true end
    return R.ContainsAny(norm, {
        "left", "right", "up", "down", "x position", "y position",
        "x offset", "y offset", "x pos", "y pos",
        "above", "below", "under", "over", "next to", "beside",
        "closer", "farther", "further", "apart", "together",
        "anchor to", "attach to", "attached to", "relative to",
        "links", "rechts", "hoch", "runter", "oben", "unten",
    })
end

function A.RouterLooksLikeMovementSettingTopic(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.LooksLikeFrameCombatMovementQuestion(norm) then return true end
    if R.LooksLikeMovementCapabilityQuestion(norm) then return true end
    if R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_EXCLUDED_TOPICS) then return false end
    if A.RouterIndicatorProblemTerms and R.ContainsAny(norm, A.RouterIndicatorProblemTerms.indicator) then return false end
    if R.ContainsAny(norm, { "lock frames", "unlock frames", "frame lock", "lock unit frames", "unlock unit frames" }) then return true end
    if not R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_TERMS) and not R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_PROBLEM_TERMS) then return false end
    local unit = R.UnitFrameScopeFromText(norm)
    local groupScope = R.GroupScopeFromText(norm)
    return unit ~= nil or groupScope ~= nil or R.ContainsAny(norm, { "unit frame", "unit frames", "frames", "frame" })
end

A.RouterTryMovementSettingShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    if R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_EXCLUDED_TOPICS) then return nil end
    if A.RouterIndicatorProblemTerms and R.ContainsAny(norm, A.RouterIndicatorProblemTerms.indicator) then return nil end

    if R.LooksLikeFrameCombatMovementQuestion(norm) then
        return R.MovementSettingReply(
            "Combat lockdown help",
            "WoW blocks protected UI changes while you are in combat. MSUF can still answer questions, but some frame movement, layout, secure-click, and protected frame changes have to wait until combat ends. Leave combat, then use MSUF Edit Mode or exact X/Y and anchor commands.",
            "enter MSUF edit mode out of combat; move target frame right 10 after combat; open anchor picker; run checks.",
            "Enter Edit Mode | Open Anchor Picker | Run Checks",
            "info"
        )
    end

    local asksLocation = R.AsksSettingLocation(norm)
    local hasProblem = R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_PROBLEM_TERMS)
        or (R.ContainsAny(norm, { "why can't", "why cant", "why can not", "why cannot", "why won't", "why wont" })
            and R.ContainsAny(norm, { "move", "drag", "anchor", "position" }))
    local asksCapability = R.LooksLikeMovementCapabilityQuestion(norm)
    local hasMovementTopic = R.ContainsAny(norm, R.UNIT_FRAME_MOVEMENT_TERMS) or hasProblem or asksCapability
    if not hasMovementTopic then return nil end
    if not asksLocation and not hasProblem and not (asksCapability and not R.HasConcreteMovementChangeDetail(norm)) then return nil end

    if R.ContainsAny(norm, { "lock frames", "unlock frames", "frame lock", "lock unit frames", "unlock unit frames" })
        and not R.UnitFrameScopeFromText(norm)
        and not R.GroupScopeFromText(norm)
    then
        return R.MovementSettingReply(
            "Frame movement / lock help",
            "MSUF unit frames are positioned through each frame page and MSUF Edit Mode; there is no single universal lock-all-unit-frames toggle. For helper widgets such as the combat timer, their lock toggles live in Gameplay. For unit frames, enter MSUF Edit Mode when you want visual dragging, or use X/Y Position and Anchor settings for exact placement.",
            "enter MSUF edit mode; open player; open target; open gameplay.",
            "Enter Edit Mode | Open Player | Open Target | Open Gameplay",
            "info"
        )
    end

    local unit, unitLabel = R.UnitFrameScopeFromText(norm)
    if unit then
        local wantsAnchor = R.ContainsAny(norm, { "anchor", "anchor to", "anchor point", "custom anchor", "custom anchor frame" })
        local wantsReset = R.ContainsAny(norm, { "reset position", "reset frame position", "default position", "restore position", "restore default position" })
            or (R.ContainsAny(norm, { "reset", "restore" }) and R.ContainsAny(norm, { "position", "placement" }))
        local title = unitLabel .. " Position setting location"
        local body
        local examples
        local actions
        if wantsAnchor then
            local anchorExampleTarget = "player"
            if R.ContainsAny(norm, { "to target", "anchor to target", "on target" }) then
                anchorExampleTarget = "target"
            elseif R.ContainsAny(norm, { "to focus", "anchor to focus", "on focus" }) then
                anchorExampleTarget = "focus"
            elseif R.ContainsAny(norm, { "to player", "anchor to player", "on player" }) then
                anchorExampleTarget = "player"
            end
            title = unitLabel .. " Anchor setting location"
            body = unitLabel .. " Anchor to, " .. unitLabel .. " Anchor Point, and " .. unitLabel .. " Custom Anchor Frame live on the " .. unitLabel .. " frame page. Use a question like this to find the setting; use a direct command when you want me to actually change it."
            examples = "open " .. unit .. "; set " .. unit .. " frame anchor to " .. anchorExampleTarget .. "; set " .. unit .. " anchor point center; open anchor picker."
            actions = "Open " .. unitLabel .. " | Open Anchor Picker | set " .. unit .. " frame anchor to " .. anchorExampleTarget
        elseif wantsReset then
            body = unitLabel .. " frame position can be restored with the reset-position action, while exact placement lives on the " .. unitLabel .. " page as " .. unitLabel .. " X Position, " .. unitLabel .. " Y Position, Anchor to, Anchor Point, and Custom Anchor Frame. I do not reset it from a location question."
            examples = "open " .. unit .. "; reset " .. unit .. " frame position; move " .. unit .. " frame down 10."
            actions = "Open " .. unitLabel .. " | reset " .. unit .. " frame position | Enter Edit Mode"
        elseif asksCapability and not asksLocation and not R.HasConcreteMovementChangeDetail(norm) then
            title = unitLabel .. " frame movement help"
            body = "Yes. I can help move the " .. unitLabel .. " frame. Use MSUF Edit Mode for visual dragging, or give me an exact direction/amount or X/Y position. I will not guess a new position from only 'move it'."
            examples = "enter MSUF edit mode; move " .. unit .. " frame right 10; set " .. unit .. " x position to 240; open " .. unit .. "."
            actions = "Enter Edit Mode | Open " .. unitLabel .. " | Open Anchor Picker"
            return R.MovementSettingReply(title, body, examples, actions, "info")
        elseif hasProblem and not asksLocation then
            title = unitLabel .. " frame movement help"
            body = "Unit frame position help: " .. unitLabel .. " frame dragging depends on MSUF Edit Mode, WoW combat lockdown, and the frame's X/Y Position plus Anchor settings. Leave combat, enter MSUF Edit Mode for visual dragging, or use a direct move command for exact placement."
            examples = "enter MSUF edit mode; move " .. unit .. " frame down 10; open " .. unit .. "; open anchor picker."
            actions = "Enter Edit Mode | Open " .. unitLabel .. " | Open Anchor Picker"
            return R.MovementSettingReply(title, body, examples, actions, "info")
        else
            body = unitLabel .. " frame position lives on the " .. unitLabel .. " frame page as " .. unitLabel .. " X Position, " .. unitLabel .. " Y Position, Anchor to, Anchor Point, and Custom Anchor Frame. For visual dragging, enter MSUF Edit Mode; for exact changes, give me a direction or coordinate."
            examples = "open " .. unit .. "; move " .. unit .. " frame right 10; set " .. unit .. " x position to 240; open anchor picker."
            actions = "Open " .. unitLabel .. " | Enter Edit Mode | Open Anchor Picker"
        end
        return R.MovementSettingReply(title, body, examples, actions)
    end

    local groupScope, groupLabel = R.GroupScopeFromText(norm)
    if groupScope then
        if asksCapability and not asksLocation and not R.HasConcreteMovementChangeDetail(norm) then
            return R.MovementSettingReply(
                groupLabel .. " frame movement help",
                "Yes. I can help move " .. groupLabel .. " frames. Use MSUF Edit Mode for visual dragging, or use Group Layout for exact X/Y position and anchor settings.",
                "enter MSUF edit mode; move " .. groupScope .. " frames down 10; set " .. groupScope .. " x position to 100; open group layout.",
                "Enter Edit Mode | Open Group Layout",
                "info"
            )
        end
        return R.MovementSettingReply(
            groupLabel .. " Frame Position setting location",
            groupLabel .. " frame placement lives in Group Layout and the group frame anchor settings. Use " .. groupLabel .. " X Position, " .. groupLabel .. " Y Position, Anchor to, Anchor Point, and Custom Anchor Frame for exact placement; use MSUF Edit Mode when you want visual dragging.",
            "open group layout; move " .. groupScope .. " frames down 10; set " .. groupScope .. " x position to 100.",
            "Open Group Layout | Enter Edit Mode"
        )
    end

    if hasProblem then
        return R.MovementSettingReply(
            "Edit Mode troubleshooting help",
            "Frame movement depends on MSUF Edit Mode, each frame's X/Y Position and Anchor settings, and WoW combat lockdown. Leave combat, enter MSUF Edit Mode for dragging, or name a frame plus direction for an exact move.",
            "enter MSUF edit mode; move player frame down 10; open anchor picker; run checks.",
            "Enter Edit Mode | Open Anchor Picker | Run Checks",
            "info"
        )
    end

    if asksCapability and not asksLocation and not R.HasConcreteMovementChangeDetail(norm) then
        return R.MovementSettingReply(
            "Frame movement help",
            "Yes. I can help move MSUF frames. Use MSUF Edit Mode for visual dragging, or name a frame plus a direction/amount for an exact move.",
            "enter MSUF edit mode; move player frame down 10; move raid frames right 20; open anchor picker.",
            "Enter Edit Mode | Open Anchor Picker",
            "info"
        )
    end

    return nil
end

R.UNIT_FRAME_SETTING_EXCLUDED_TOPICS = {
    "aura", "auras", "buff", "buffs", "debuff", "debuffs", "castbar", "cast bar",
    "power bar", "powerbar", "power text", "health text", "name text", "font", "text",
    "border", "border color", "outline",
    "raid marker", "role icon", "ready check", "leader icon", "pvp icon", "resting icon",
    "focus kick", "kick tracker", "interrupt tracker",
    "combat timer", "combat crosshair", "totem",
}

function A.RouterLooksLikeUnitFrameSettingTopic(text)
    local norm = R.Normalize(text)
    if norm == "" or not R.AsksSettingLocation(norm) then return false end
    if R.ContainsAny(norm, R.UNIT_FRAME_SETTING_EXCLUDED_TOPICS) then return false end
    local unit = R.UnitFrameScopeFromText(norm)
    if not unit then return false end
    return R.ContainsAny(norm, {
        "width", "height", "size", "scale", "portrait", "portrait style",
        "model portrait", "class portrait", "frame size", "frame width", "frame height",
    })
end

A.RouterTryUnitFrameSettingShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" or not R.AsksSettingLocation(norm) then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end
    if R.ContainsAny(norm, R.UNIT_FRAME_SETTING_EXCLUDED_TOPICS) then return nil end

    local unit, unitLabel = R.UnitFrameScopeFromText(norm)
    if not unit or not unitLabel then return nil end

    if R.ContainsAny(norm, { "portrait", "portrait style", "model portrait", "class portrait" }) then
        return R.MovementSettingReply(
            unitLabel .. " Portrait setting location",
            unitLabel .. " portrait options live on the " .. unitLabel .. " frame page. Use " .. unitLabel .. " Portrait, Portrait Style, Portrait Position/Side, and keep-visible portrait options there; use a direct command only when you want me to change it.",
            "open " .. unit .. "; set " .. unit .. " portrait style to class; set " .. unit .. " portrait position left.",
            "Open " .. unitLabel .. " | set " .. unit .. " portrait style to class"
        )
    end

    if R.ContainsAny(norm, { "width", "wide", "wider", "frame width" }) then
        return R.MovementSettingReply(
            unitLabel .. " Width setting location",
            unitLabel .. " Width lives on the " .. unitLabel .. " frame page. Use it with " .. unitLabel .. " Height and scale settings when the whole frame size should change.",
            "open " .. unit .. "; set " .. unit .. " width to 250; make " .. unit .. " frame wider.",
            "Open " .. unitLabel .. " | set " .. unit .. " width to 250"
        )
    end

    if R.ContainsAny(norm, { "height", "high", "taller", "frame height" }) then
        return R.MovementSettingReply(
            unitLabel .. " Height setting location",
            unitLabel .. " Height lives on the " .. unitLabel .. " frame page. Use it with " .. unitLabel .. " Width and scale settings when the whole frame size should change.",
            "open " .. unit .. "; set " .. unit .. " height to 40; make " .. unit .. " frame taller.",
            "Open " .. unitLabel .. " | set " .. unit .. " height to 40"
        )
    end

    if R.ContainsAny(norm, { "size", "bigger", "larger", "smaller", "scale", "frame size" }) then
        return R.MovementSettingReply(
            unitLabel .. " Size setting location",
            unitLabel .. " frame size lives on the " .. unitLabel .. " page. Start with " .. unitLabel .. " Width and " .. unitLabel .. " Height; use scale only when you need the entire frame to grow or shrink together.",
            "open " .. unit .. "; set " .. unit .. " width to 250; set " .. unit .. " height to 40.",
            "Open " .. unitLabel .. " | set " .. unit .. " width to 250"
        )
    end

    return nil
end

function R.AuraLaneFromText(norm)
    if R.ContainsAny(norm, { "debuff", "debuffs" }) then return "debuff", "Debuff", "Debuffs" end
    if R.ContainsAny(norm, { "buff", "buffs" }) then return "buff", "Buff", "Buffs" end
    return nil, nil, nil
end

function R.AuraSettingKindFromText(norm)
    if R.ContainsAny(norm, { "icon size", "icons bigger", "icons larger", "icon bigger", "icon larger", "bigger", "larger", "smaller", "size" }) then
        return "size", "Icon Size"
    end
    if R.ContainsAny(norm, { "max icons", "maximum icons", "icon count", "count", "how many", "per row", "icons per row", "wrap count", "row count" }) then
        return "count", "Max Icons"
    end
    if R.ContainsAny(norm, { "wrong side", "other side", "move", "position", "anchor", "offset", "growth", "grow", "direction", "layout" }) then
        return "layout", "Layout"
    end
    return "visibility", "Visibility"
end

A.RouterAuraDetailReply = function(title, body, examples, actions, status)
    local reply = A.RouterAuraProblemReply and A.RouterAuraProblemReply(title, body, examples, actions) or {
        text = tostring(title or "Aura help") .. "\n" .. tostring(body or ""),
        summary = "Assistant aura help",
    }
    reply.status = status or "applied"
    reply.result = reply.status
    return reply
end

function R.AuraHasBothLanes(norm)
    return R.ContainsAny(norm, { "buff", "buffs" }) and R.ContainsAny(norm, { "debuff", "debuffs" })
end

function R.AuraCompoundKeepIntent(norm)
    return R.AuraHasBothLanes(norm) and R.ContainsAny(norm, {
        "but keep", "keep buffs", "keep debuffs", "while keeping", "leave buffs", "leave debuffs",
        "do not change buffs", "do not change debuffs", "dont change buffs", "dont change debuffs",
    })
end

function R.AuraScopeForDetailText(norm)
    local groupScope, groupLabel = R.GroupScopeFromText(norm)
    if groupScope and groupLabel then return groupScope, groupLabel, true end
    local unit, unitLabel = R.UnitScopeFromText(norm)
    if unit and unitLabel then return unit, unitLabel, false end
    return nil, nil, false
end

function R.AuraDetailPageForScope(groupScope, lane)
    if groupScope then return "Group Auras" end
    return lane == "buff" and "Aura Buffs" or "Aura Debuffs"
end

function R.AuraSpecificIconFilterRequest(norm)
    if not (R.WantsVisibilityOff(norm) or R.AsksSettingLocation(norm)) then return false end
    if not R.ContainsAny(norm, { "icon", "icons", "symbol" }) then return false end
    if R.ContainsAny(norm, { "buff icons", "debuff icons", "aura icons", "buff icon size", "debuff icon size", "aura icon size" }) then return false end
    return R.ContainsAny(norm, { "buff", "buffs", "debuff", "debuffs", "aura", "auras" })
end

function R.AuraSpecificSpellRequest(norm)
    if not R.WantsVisibilityOff(norm) then return false end
    return R.ContainsAny(norm, { "spell ", "spell:", "power word shield" })
end

function R.AuraDetailExplicitNumber(norm)
    local value = tostring(norm or ""):match("%f[%w]to%s+(-?%d+%.?%d*)%f[^%w]")
        or tostring(norm or ""):match("%f[%w]auf%s+(-?%d+%.?%d*)%f[^%w]")
        or tostring(norm or ""):match("%f[%w]zu%s+(-?%d+%.?%d*)%f[^%w]")
    if value then return value end
    if R.ContainsAny(norm, { "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink" }) then return nil end
    return tostring(norm or ""):match("(-?%d+%.?%d*)%s*$")
end

A.RouterTryAuraDetailSettingShortcut = function(norm, coreHandler)
    local asksLocation = R.AsksSettingLocation(norm)
    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm)
    local scope, scopeLabel, isGroupScope = R.AuraScopeForDetailText(norm)
    local lane, laneLabel, lanePlural = R.AuraLaneFromText(norm)

    if R.AuraSpecificSpellRequest(norm) and scope and type(coreHandler) == "function" then
        local P = A.Parser or {}
        local value = type(P.AuraBlacklistSpellValue) == "function" and P.AuraBlacklistSpellValue(norm) or nil
        if type(value) == "string" and value ~= "" then
            if asksLocation then
                local laneText = lane and (" " .. laneLabel) or ""
                return A.RouterAuraDetailReply(
                    scopeLabel .. laneText .. " hidden aura setting location",
                    "Saved exact aura hiding data is shown in Aura Filters, but it is read-only while the native 12.1 backend is active. Open Aura Filters, set Aura Editing Scope to " .. scopeLabel .. ", then use live filter toggles/tokens for display changes. I did not change the frame or its power text.",
                    "open aura filters; set " .. scope .. (lane and (" " .. lane:lower() .. " ") or " ") .. "raid filter on.",
                    "Open Aura Filters | Check " .. scopeLabel .. " Auras"
                )
            end
            local laneText = lane and (" " .. lane:lower() .. "s") or " auras"
            local result = R.CoreControl(
                coreHandler,
                "hide " .. tostring(value) .. " for " .. tostring(scope) .. laneText,
                "That looks like a specific aura. Exact SpellID blacklist edits are read-only while the native 12.1 backend is active, so use live Aura Filters instead of disabling the whole frame or aura lane.",
                "info"
            )
            if result then return result end
        end
    end

    if lane and scope and R.AuraSpecificIconFilterRequest(norm) then
        return A.RouterAuraDetailReply(
            scopeLabel .. " " .. laneLabel .. " specific icon filter",
            "That sounds like one specific " .. laneLabel:lower() .. " icon, not the whole " .. scopeLabel .. " " .. lanePlural .. " lane. Exact SpellID hiding is read-only in the native 12.1 backend, so use Aura Filters for live filter changes. I will not hide all " .. scopeLabel .. " " .. lanePlural .. " for one icon name.",
            "open aura filters; set " .. scope .. " " .. lane:lower() .. " raid filter on; where can I adjust " .. scope .. " " .. lane:lower() .. " filters.",
            "Open Aura Filters | Check " .. scopeLabel .. " " .. laneLabel,
            asksLocation and "applied" or "info"
        )
    end

    local broadCooldownText = R.ContainsAny(norm, { "cooldown text", "timer text" })
    local broadStackText = R.ContainsAny(norm, { "stack text", "stack count", "count text", "stacks" })
    if scope and not lane and (broadCooldownText or broadStackText) then
        local textName = broadCooldownText and "cooldown text" or "stack text"
        local settingLabel = broadCooldownText and "Cooldown Text" or "Stack Text"
        local sizeLabel = broadCooldownText and "Cooldown Text Size" or "Stack Text Size"
        local sizeIntent = R.ContainsAny(norm, { "size", "groesse", "grosse", "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink" })
        if isGroupScope then
            return A.RouterAuraDetailReply(
                scopeLabel .. " aura " .. settingLabel .. " needs a lane",
                scopeLabel .. " aura " .. settingLabel .. " has separate Buff and Debuff controls. Tell me which lane so I do not change the wrong group aura text setting.",
                "make " .. scope .. " buff " .. textName .. " size bigger; make " .. scope .. " debuff " .. textName .. " size bigger; turn off " .. scope .. " debuff " .. textName .. ".",
                "Open Group Auras | " .. scopeLabel .. " Buff " .. settingLabel .. " | " .. scopeLabel .. " Debuff " .. settingLabel,
                asksLocation and "applied" or "ambiguous"
            )
        end
        local command
        if sizeIntent then
            local explicitNumber = R.AuraDetailExplicitNumber(norm)
            if explicitNumber then
                command = "set " .. scope .. " " .. textName .. " size to " .. explicitNumber
            else
                local direction = R.ContainsAny(norm, { "smaller", "decrease", "reduce", "shrink" }) and "smaller" or "bigger"
                command = "make " .. scope .. " " .. textName .. " size " .. direction
            end
            settingLabel = sizeLabel
        else
            local verb = wantsOff and "turn off " or "turn on "
            command = verb .. scope .. " " .. textName
        end
        if asksLocation then
            local locationLabel = broadCooldownText and "Cooldown Text" or "Stack Text"
            return A.RouterAuraDetailReply(
                scopeLabel .. " Aura " .. locationLabel .. " setting location",
                scopeLabel .. " Aura " .. locationLabel .. " lives in Aura Style. Use Aura Style for cooldown/stack text size, visibility, anchor, and offsets for that unit scope, separate from Buff/Debuff icon layout.",
                command .. "; open aura style.",
                "Open Aura Style | " .. command
            )
        end
        local result = R.CoreControl(coreHandler, command, scopeLabel .. " Aura " .. settingLabel .. " is in Aura Style.", "info")
        if result then return result end
    end

    if not lane or not scope then return nil end

    local page = R.AuraDetailPageForScope(isGroupScope, lane)
    local function locationReply(settingLabel, command)
        return A.RouterAuraDetailReply(
            scopeLabel .. " " .. laneLabel .. " " .. settingLabel .. " setting location",
            scopeLabel .. " " .. laneLabel .. " " .. settingLabel .. " is an aura detail control. Open " .. page .. " and use the " .. scopeLabel .. " " .. laneLabel .. " " .. settingLabel .. " option; this is separate from hiding the entire " .. lanePlural .. " lane.",
            command .. "; open " .. page:lower() .. "; check " .. scope .. " " .. lanePlural:lower() .. ".",
            "Open " .. page .. " | " .. command
        )
    end

    local function run(command, fallback)
        if asksLocation then return nil end
        if type(coreHandler) ~= "function" then return nil end
        return R.CoreControl(coreHandler, command, fallback, "info")
    end

    if R.ContainsAny(norm, { "only my buffs", "my buffs only", "only my debuffs", "my debuffs only", "only mine" }) then
        local command
        if isGroupScope then
            command = "set " .. scope .. " " .. lane .. " filter to player"
        else
            command = "turn on " .. scope .. " " .. lane .. " player filter"
        end
        if asksLocation then return locationReply("Player Filter", command) end
        local result = run(command, scopeLabel .. " " .. laneLabel .. " Player Filter is in Aura Filters.")
        if result then return result end
    end

    if lane == "debuff" and R.ContainsAny(norm, { "dispellable", "dispel" }) then
        local command
        if isGroupScope then
            command = "set " .. scope .. " debuff filter to dispellable"
        else
            command = "turn on " .. scope .. " debuff dispellable filter"
        end
        if asksLocation then return locationReply("Dispellable Filter", command) end
        local result = run(command, scopeLabel .. " Debuff Dispellable Filter is in Aura Filters.")
        if result then return result end
    end

    if R.ContainsAny(norm, { "cooldown swipe", "timer swipe" }) then
        local verb = wantsOff and "turn off " or "turn on "
        local command = verb .. scope .. " " .. lane .. " cooldown swipe"
        if asksLocation then return locationReply("Cooldown Swipe", command) end
        local result = run(command, scopeLabel .. " " .. laneLabel .. " Cooldown Swipe is in aura style controls.")
        if result then return result end
    end

    if R.ContainsAny(norm, { "cooldown text", "timer text" }) then
        local settingLabel = "Cooldown Text"
        local command
        if R.ContainsAny(norm, { "size", "groesse", "grosse", "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink" }) then
            settingLabel = isGroupScope and "Cooldown Font Size" or "Cooldown Text Size"
            local explicitNumber = R.AuraDetailExplicitNumber(norm)
            if explicitNumber then
                command = "set " .. scope .. " " .. lane .. " cooldown text size to " .. explicitNumber
            else
                local direction = R.ContainsAny(norm, { "smaller", "decrease", "reduce", "shrink" }) and "smaller" or "bigger"
                command = "make " .. scope .. " " .. lane .. " cooldown text size " .. direction
            end
        else
            local verb = wantsOff and "turn off " or "turn on "
            command = verb .. scope .. " " .. lane .. " cooldown text"
        end
        if asksLocation then return locationReply(settingLabel, command) end
        local result = run(command, scopeLabel .. " " .. laneLabel .. " " .. settingLabel .. " is in aura style controls.")
        if result then return result end
    end

    if R.ContainsAny(norm, { "stack text", "stack count", "count text", "stacks" }) then
        local settingLabel = "Stack Count"
        local command
        if R.ContainsAny(norm, { "size", "groesse", "grosse", "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink" }) then
            settingLabel = isGroupScope and "Stack Font Size" or "Stack Text Size"
            local explicitNumber = R.AuraDetailExplicitNumber(norm)
            if explicitNumber then
                command = "set " .. scope .. " " .. lane .. " stack text size to " .. explicitNumber
            else
                local direction = R.ContainsAny(norm, { "smaller", "decrease", "reduce", "shrink" }) and "smaller" or "bigger"
                command = "make " .. scope .. " " .. lane .. " stack text size " .. direction
            end
        else
            local verb = wantsOff and "turn off " or "turn on "
            command = verb .. scope .. " " .. lane .. " stack count"
        end
        if asksLocation then return locationReply(settingLabel, command) end
        local result = run(command, scopeLabel .. " " .. laneLabel .. " " .. settingLabel .. " is in aura style controls.")
        if result then return result end
    end

    return nil
end

A.RouterTryAuraSettingShortcut = function(norm, coreHandler)
    local asksLocation = R.AsksSettingLocation(norm)
    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm)
    local displayOnly = asksLocation and R.IsDisplayOnlySettingsRequest(norm)
    if displayOnly then
        wantsOff, wantsOn = false, false
    end
    if not asksLocation and not wantsOff and not wantsOn then return nil end
    if R.AuraCompoundKeepIntent(norm) then return nil end

    local unit, unitLabel = R.UnitScopeFromText(norm)
    local groupScope, groupLabel = R.GroupScopeFromText(norm)
    local lane, laneLabel, lanePlural = R.AuraLaneFromText(norm)
    if not lane then return nil end

    local kind, kindLabel = R.AuraSettingKindFromText(norm)
    local scope = groupScope or unit
    local scopeLabel = groupLabel or unitLabel
    if not scope or not scopeLabel then return nil end

    if not asksLocation and R.ContainsAny(norm, { "blacklist", "hidden aura", "hidden spell", "hidden spells", "spell blacklist", "spell filter" }) then
        return nil
    end

    if asksLocation and R.ContainsAny(norm, { "blacklist", "whitelist", "hidden aura", "hidden spell", "spell blacklist", "spell filter", "filter" }) then
        local reply = A.RouterAuraProblemReply(
            scopeLabel .. " " .. laneLabel .. " Filter setting location",
            scopeLabel .. " " .. laneLabel .. " filtering lives in Aura Filters. Open Aura Filters, set Aura Editing Scope to " .. scopeLabel .. ", set Aura Filter Lane to " .. lanePlural .. ", then use live filter toggles/tokens for that lane. Saved exact blacklist/whitelist data is read-only in the native 12.1 backend.",
            "open aura filters; set aura editing scope to " .. scope .. "; set aura filter lane to " .. lane:lower() .. "s; set " .. scope .. " " .. lane:lower() .. " raid filter on.",
            "Open Aura Filters | Check " .. scopeLabel .. " " .. laneLabel
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.PageFollowupResults("auras3_filters", "Aura Filters", scopeLabel .. " " .. laneLabel .. " filtering lives in Aura Filters.")
        return reply
    end

    local page = groupScope and "Group Auras" or (lane == "buff" and "Aura Buffs" or "Aura Debuffs")
    local settingLabel = scopeLabel .. " " .. laneLabel .. (kind == "visibility" and "s" or (" " .. kindLabel))
    local commandNoun = scope .. " " .. lane .. (kind == "visibility" and " visibility" or (" " .. kindLabel:lower()))
    if groupScope then commandNoun = scope .. " " .. lane .. (kind == "visibility" and "s" or (" " .. kindLabel:lower())) end

    if asksLocation then
        local body = page .. " help: " .. settingLabel .. " lives on " .. page .. ". Open " .. page .. " and use the " .. settingLabel .. " control for that frame or group scope."
        if kind == "layout" then
            body = page .. " help: " .. scopeLabel .. " " .. lanePlural .. " layout lives on " .. page .. ". Open " .. page .. " and use anchor, growth, X/Y offset, icon size, and per-row controls for that lane."
        end
        if displayOnly then
            if type(coreHandler) == "function" then coreHandler("open " .. page:lower()) end
            body = "Done. Opened " .. page .. ".\n" .. body
        end
        local verb = wantsOff and "turn off " or (wantsOn and "turn on " or "turn off ")
        local example = kind == "visibility" and (verb .. scope .. " " .. lane .. " visibility")
            or ("set " .. scope .. " " .. lane .. " icon size to 30")
        local reply = A.RouterAuraProblemReply(
            settingLabel .. " setting location",
            body,
            example .. "; open " .. page:lower() .. "; check " .. scope .. " " .. lanePlural:lower() .. ".",
            "Open " .. page .. " | " .. example
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
        return reply
    end

    if kind == "visibility" and type(coreHandler) == "function" then
        local verb = wantsOff and "turn off " or "turn on "
        local result = R.CoreControl(
            coreHandler,
            verb .. scope .. " " .. lane .. " visibility",
            settingLabel .. " is on " .. page .. ". Ask: open " .. page:lower() .. ", or " .. verb .. scope .. " " .. lane .. " visibility.",
            "info"
        )
        if result then return result end
    end

    return nil
end

A.RouterTryGroupNaturalSettingShortcut = function(norm, coreHandler)
    local scope, scopeLabel = R.GroupScopeFromText(norm)
    if not scope then return nil end

    local asksLocation = R.AsksSettingLocation(norm)
    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm)
    if asksLocation and R.IsDisplayOnlySettingsRequest(norm) then
        wantsOff, wantsOn = false, false
    end
    local mentionsClickCasting = R.ContainsAny(norm, { "click casting", "click-casting", "clickcast", "click cast", "mouseover healing", "mouse over healing" })
    local mentionsColumns = R.ContainsAny(norm, { "columns", "column", "max columns", "units per column", "players per column", "frames per column" })
    local mentionsWidth = R.ContainsAny(norm, { "wider", "width", "wide", "frame width" })
    local mentionsHeight = R.ContainsAny(norm, { "taller", "height", "high", "frame height" })
    local mentionsSpacing = R.ContainsAny(norm, { "spacing", "space between", "gap between", "frame spacing", "closer together", "farther apart", "distance between" })
    local mentionsText = R.ContainsAny(norm, {
        "name text", "names", "name font", "name size", "name text size",
        "health text", "hp text", "health font", "health text size", "hp font", "hp text size",
        "power text", "mana text", "power font", "power text size", "mana text size",
        "text size", "font size",
    })

    if asksLocation and mentionsText then
        local textLabel = "Text"
        local commandNoun = "name text size"
        if R.ContainsAny(norm, { "health text", "hp text", "health font", "health text size", "hp font", "hp text size" }) then
            textLabel = "HP Font Size"
            commandNoun = "hp font size"
        elseif R.ContainsAny(norm, { "power text", "mana text", "power font", "power text size", "mana text size" }) then
            textLabel = "Power Font Size"
            commandNoun = "power font size"
        elseif R.ContainsAny(norm, { "name text", "names", "name font", "name size", "name text size", "font size", "text size" }) then
            textLabel = "Name Font Size"
            commandNoun = "name font size"
        end
        local reply = A.RouterGroupLayoutReply(
            scopeLabel .. " " .. textLabel .. " setting location",
            scopeLabel .. " " .. textLabel .. " lives in Group Health & Text. Open Group Health & Text and use the " .. scopeLabel .. " text visibility, font size, text slot, delimiter, offset, and layer controls for that group scope.",
            "open group health and text; set " .. scope .. " " .. commandNoun .. " to 12; turn on " .. scope .. " names.",
            "Open Group Health & Text | set " .. scope .. " " .. commandNoun .. " to 12"
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(scopeLabel .. " " .. textLabel, scopeLabel .. " " .. textLabel)
            or R.PageFollowupResults("gf_bars", "Group Health & Text", scopeLabel .. " text controls live in Group Health & Text.")
        return reply
    end

    if asksLocation and mentionsClickCasting then
        local verb = wantsOff and "turn off " or "turn on "
        local reply = A.RouterGroupLayoutReply(
            scopeLabel .. " Click Casting setting location",
            scopeLabel .. " Click Casting lives in Group Layout. Open Group Layout and use " .. scopeLabel .. " Click Casting for that group scope.",
            verb .. scope .. " click casting; open group layout; check " .. scope .. " frames.",
            "Open Group Layout | " .. verb .. scope .. " click casting"
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(scopeLabel .. " Click Casting", scopeLabel .. " Click Casting")
            or R.PageFollowupResults("gf_layout", "Group Layout", scopeLabel .. " Click Casting lives in Group Layout.")
        return reply
    end

    if asksLocation and mentionsColumns then
        local reply = A.RouterGroupLayoutReply(
            scopeLabel .. " Max Columns setting location",
            scopeLabel .. " column options live in Group Layout. Use " .. scopeLabel .. " Max Columns and " .. scopeLabel .. " Units Per Column for column layout.",
            "set " .. scope .. " max columns to 5; set " .. scope .. " units per column to 5; open group layout.",
            "Open Group Layout | set " .. scope .. " max columns to 5"
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(scopeLabel .. " Max Columns", scopeLabel .. " Max Columns")
            or R.PageFollowupResults("gf_layout", "Group Layout", scopeLabel .. " column controls live in Group Layout.")
        return reply
    end

    if asksLocation and mentionsSpacing then
        local reply = A.RouterGroupLayoutReply(
            scopeLabel .. " Spacing setting location",
            scopeLabel .. " Spacing lives in Group Layout. Use it for the gap between frames; Width, Height, Growth Direction, Max Columns, and Units Per Column are nearby layout controls.",
            "open group layout; set " .. scope .. " spacing to 2; make " .. scope .. " frames closer together.",
            "Open Group Layout | set " .. scope .. " spacing to 2"
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(scopeLabel .. " Spacing", scopeLabel .. " Spacing")
            or R.PageFollowupResults("gf_layout", "Group Layout", scopeLabel .. " spacing controls live in Group Layout.")
        return reply
    end

    if asksLocation and (mentionsWidth or mentionsHeight) then
        local dimension = mentionsHeight and "Height" or "Width"
        local reply = A.RouterGroupLayoutReply(
            scopeLabel .. " " .. dimension .. " setting location",
            scopeLabel .. " " .. dimension .. " lives in Group Layout. Open Group Layout and use " .. scopeLabel .. " " .. dimension .. " to change the group-frame size.",
            "set " .. scope .. " " .. dimension:lower() .. " to 140; increase " .. scope .. " " .. dimension:lower() .. "; open group layout.",
            "Open Group Layout | set " .. scope .. " " .. dimension:lower() .. " to 140"
        )
        reply.status = "applied"
        reply.result = "applied"
        return reply
    end

    if mentionsClickCasting and (wantsOff or wantsOn) and type(coreHandler) == "function" then
        local verb = wantsOff and "turn off " or "turn on "
        return R.CoreControl(
            coreHandler,
            verb .. scope .. " click casting",
            scopeLabel .. " Click Casting lives in Group Layout. Ask: open group layout, or " .. verb .. scope .. " click casting.",
            "info"
        )
    end

    if mentionsWidth and R.ContainsAny(norm, { "make", "increase", "bigger", "larger", "wider" }) and type(coreHandler) == "function" then
        return R.CoreControl(coreHandler, "increase " .. scope .. " width", scopeLabel .. " Width lives in Group Layout.", "info")
    end

    if mentionsHeight and R.ContainsAny(norm, { "make", "increase", "bigger", "larger", "taller" }) and type(coreHandler) == "function" then
        return R.CoreControl(coreHandler, "increase " .. scope .. " height", scopeLabel .. " Height lives in Group Layout.", "info")
    end

    return nil
end

A.RouterTryGroupLayoutProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end
    local terms = A.RouterGroupLayoutProblemTerms
    local mentionsGroup = R.ContainsAny(norm, terms.group)
    local mentionsClickCasting = R.ContainsAny(norm, terms.clickCasting)
    if not mentionsGroup and not mentionsClickCasting then return nil end
    local concreteMutation = R.StartsWithMutationCommand(norm)

    local naturalSettingResult = A.RouterTryGroupNaturalSettingShortcut and A.RouterTryGroupNaturalSettingShortcut(norm, coreHandler)
    if naturalSettingResult then return naturalSettingResult end

    if mentionsClickCasting and R.ContainsAny(norm, { "not working", "does not work", "doesn't work", "broken", "not clickable", "cannot click", "can't click", "cant click" }) then
        return A.RouterGroupLayoutReply(
            "Mouseover and click casting help",
            "MSUF can enable Click Casting on Party, Raid, and Mythic Raid frames, but spell bindings come from WoW's click-cast/keybind system or a click-casting addon. First make sure the relevant group frame is enabled and click casting is enabled for that frame type.",
            "turn on raid click casting; turn on party click casting; open group layout.",
            "Open Group Layout | Check Party Frames | Check Raid Frames"
        )
    end

    if mentionsGroup and R.ContainsAny(norm, terms.blizzardFallback)
        and R.ContainsAny(norm, { "show", "showing", "visible", "instead", "fallback", "wrong" })
    then
        return A.RouterGroupLayoutReply(
            "Blizzard group-frame fallback help",
            "Blizzard fallback controls what happens to Blizzard party or raid frames when the MSUF group frame is disabled. If Blizzard frames are showing instead of MSUF, check whether MSUF Party/Raid is enabled and set the fallback mode intentionally instead of guessing.",
            "show party group frames; set party blizzard fallback to none; set raid blizzard fallback to auto; open group layout.",
            "Open Group Layout | Check Party Frames | Check Raid Frames"
        )
    end

    if mentionsGroup and not concreteMutation and R.ContainsAny(norm, terms.sorting) then
        return A.RouterGroupLayoutReply(
            "Group sorting help",
            "Group ordering lives in Group Layout. For raid frames, check Sort by Role, Role Priority Order, Preserve Raid Groups, and player-first options before changing frame geometry.",
            "open group layout; turn on raid sort by role; set raid role priority order; turn on raid preserve raid groups.",
            "Open Group Layout"
        )
    end

    if mentionsGroup and not concreteMutation and R.ContainsAny(norm, terms.columns) then
        return A.RouterGroupLayoutReply(
            "Group columns help",
            "Group columns are controlled in Group Layout through Max Columns, Units per Column, growth direction, and raid-group preservation. Tell me the exact column count when you want me to change it.",
            "set raid max columns to 5; set raid units per column to 5; open group layout.",
            "Open Group Layout"
        )
    end

    if mentionsGroup and not concreteMutation and (R.ContainsAny(norm, terms.growth) or R.ContainsAny(norm, terms.spacing)) then
        return A.RouterGroupLayoutReply(
            "Group spacing and growth help",
            "Group spacing, growth direction, columns, width, height, and scale are all Group Layout settings. If frames overlap or spread too far apart, start with spacing and scale before changing health text or auras.",
            "set raid spacing to 4; set party growth direction to down; set raid scale for 20 players to 90; open group layout.",
            "Open Group Layout | Open Group Health & Text"
        )
    end

    if mentionsGroup and R.ContainsAny(norm, terms.rangeFade)
        and R.ContainsAny(norm, { "strong", "too", "not", "wrong", "faded", "fading" })
    then
        return A.RouterGroupLayoutReply(
            "Group range fade help",
            "Range Fade controls how transparent group frames become when units are out of range. If frames are too faded, lower the fade amount or inspect Group Health & Text for the relevant Party, Raid, or Mythic Raid scope.",
            "set raid range fade to 40; set party range fade to 60; open group health and text.",
            "Open Group Health & Text | Open Group Layout"
        )
    end

    return nil
end

function R.VisibilityGroupForText(norm)    if R.ContainsAny(norm, R.VISIBILITY_MYTHIC_TERMS) then return "mythicraid" end
    if R.ContainsAny(norm, R.VISIBILITY_PARTY_TERMS) then return "party" end
    if R.ContainsAny(norm, R.VISIBILITY_RAID_TERMS) then return "raid" end
    return nil
end

function R.VisibilityUnitForText(norm)    if R.ContainsAny(norm, R.VISIBILITY_TARGETTARGET_TERMS) then return "targettarget" end
    if R.ContainsAny(norm, R.VISIBILITY_FOCUSTARGET_TERMS) then return "focustarget" end
    if R.ContainsAny(norm, R.VISIBILITY_TARGET_TERMS) then return "target" end
    if R.ContainsAny(norm, R.VISIBILITY_FOCUS_TERMS) then return "focus" end
    if R.ContainsAny(norm, R.VISIBILITY_PET_TERMS) then return "pet" end
    if R.ContainsAny(norm, R.VISIBILITY_BOSS_TERMS) then return "boss" end
    if R.ContainsAny(norm, R.VISIBILITY_PLAYER_TERMS) then return "player" end
    return nil
end

function R.VisibilityAuraLaneForText(norm)    if R.ContainsAny(norm, R.VISIBILITY_DEBUFF_TERMS) then return "debuffs" end
    if R.ContainsAny(norm, R.VISIBILITY_BUFF_TERMS) then return "buffs" end
    return "auras"
end

function R.VisibilityAuraScopeForText(group, unit)    if group then return group end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    if not unit then return "target" end
    return nil
end

function R.VisibilityCastbarUnitForText(unit)    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    if not unit then return "target" end
    return nil
end

A.RouterAuraProblemTerms = A.RouterAuraProblemTerms or {
    aura = {
        "aura", "auras", "auren", "buff", "buffs", "debuff", "debuffs",
    },
    masque = {
        "masque", "masque skin", "masque skinning", "masque border", "masque borders",
        "masque backdrop", "masque add-on", "masque addon",
    },
    layout = {
        "wrong side", "on wrong side", "wrong position", "position is wrong",
        "wrong place", "growth is wrong", "grow wrong way", "grow the wrong way",
        "grows wrong way", "grow in the wrong direction", "anchor is wrong",
        "offset is wrong", "offset wrong",
    },
    filter = {
        "filter not working", "filter does not work", "filter doesn't work",
        "filtered wrong", "wrong filter", "filter is wrong", "blacklist not working",
        "blacklist spell not working", "whitelist not working", "hidden aura not working",
        "hidden spell not working", "spell filter not working", "only my buffs",
        "only my debuffs", "only mine",
    },
    text = {
        "cooldown text", "stack text", "timer text", "aura text", "buff text", "debuff text",
    },
}

A.RouterAuraProblemReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Aura help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open auras; check target buffs.") .. "\nYou can ask: " .. tostring(actions or "Open Auras | Open Aura Filters | Check target buffs"),
        status = "info",
        summary = "Assistant aura help",
    }
end

R.AURA_UNIT_FILTER_SPECS = {
    buff = {
        { key = "onlyMine", label = "Player filter", token = "PLAYER", effect = "shows only buffs cast by you, your pet, or your vehicle.", bestFor = "tracking your own HoTs, short buffs, or personal maintenance buffs without seeing everyone else's versions.", caution = "It is usually too strict for raid support buffs because it hides buffs cast by other players." },
        { key = "raid", label = "Raid filter", token = "RAID", effect = "keeps buffs Blizzard marks as raid-frame relevant.", bestFor = "a clean raid setup where you want important buffs and fewer harmless background icons.", caution = "It is not a hand-written MSUF spell list; Blizzard decides which buffs count as raid-relevant." },
        { key = "raidInCombat", label = "Raid in combat filter", token = "RAID_IN_COMBAT", effect = "uses Blizzard's combat-aware raid-frame visibility set.", bestFor = "the cleanest raid-combat view when you only care about things Blizzard expects raid frames to show during the pull.", caution = "It can hide useful out-of-combat or low-priority buffs." },
        { key = "includeNameplateOnly", label = "Nameplate-only filter", token = "INCLUDE_NAME_PLATE_ONLY", effect = "also allows auras Blizzard normally marks for nameplates instead of unit frames.", bestFor = "fixing a specific missing aura that appears on nameplates but not on MSUF unit frames.", caution = "Do not use it as your first raid filter; it can add nameplate-style combat noise to unit frames." },
        { key = "cancelable", label = "Cancelable filter", token = "CANCELABLE", effect = "shows buffs that can be canceled by the player.", bestFor = "debugging or trimming personal removable buffs.", caution = "Cancelable does not mean dangerous or important. It only means the buff can be removed." },
        { key = "notCancelable", label = "Not cancelable filter", token = "NOT_CANCELABLE", effect = "shows buffs that cannot be canceled by the player.", bestFor = "separating persistent/locked buffs from removable buffs.", caution = "It conflicts with Cancelable; using both would narrow the lane too hard." },
        { key = "externalDefensive", label = "External defensive filter", token = "EXTERNAL_DEFENSIVE", effect = "shows defensive cooldowns placed on the unit by someone else.", bestFor = "raid tanks and healers who want to see externals like major protection cooldowns.", caution = "It is a focused cooldown-tracking filter, not a general buff filter." },
        { key = "bigDefensive", label = "Big defensive filter", token = "BIG_DEFENSIVE", effect = "shows major defensive buffs that Blizzard classifies as big defensives.", bestFor = "tracking large personal defensives or raid survival cooldowns without all normal buffs.", caution = "It is intentionally narrow; normal buffs disappear when this is the only active buff filter." },
    },
    debuff = {
        { key = "onlyMine", label = "Player filter", token = "PLAYER", effect = "shows only debuffs applied by you, your pet, or your vehicle.", bestFor = "DPS players tracking their own DoTs, bleeds, or personal debuffs on target/focus.", caution = "It hides raid mechanics and other players' debuffs, so it is bad as a general raid-warning filter." },
        { key = "raid", label = "Raid filter", token = "RAID", effect = "keeps debuffs Blizzard marks as raid-frame relevant.", bestFor = "most raid frames: it removes random minor debuffs and keeps the ones Blizzard expects raid frames to care about.", caution = "It can still show debuffs you cannot dispel; use Dispellable if your job is dispels." },
        { key = "raidInCombat", label = "Raid in combat filter", token = "RAID_IN_COMBAT", effect = "uses Blizzard's stricter combat-aware raid-frame debuff visibility.", bestFor = "progression raid frames where clutter is worse than missing low-priority out-of-combat debuffs.", caution = "It is stricter than Raid and may hide some debuffs outside combat." },
        { key = "includeNameplateOnly", label = "Nameplate-only filter", token = "INCLUDE_NAME_PLATE_ONLY", effect = "also allows debuffs Blizzard normally marks for nameplates instead of unit frames.", bestFor = "a specific missing combat debuff that Blizzard expects on nameplates.", caution = "It can add extra enemy/nameplate tracking noise to unit frames." },
        { key = "includeDispellable", label = "Dispellable filter", token = "RAID_PLAYER_DISPELLABLE", effect = "shows debuffs with a dispel type your character can remove.", bestFor = "healers and support players who need to know what they can actually cleanse right now.", caution = "It hides important mechanics you cannot dispel, so it is not a full raid-mechanics filter by itself." },
        { key = "crowdControl", label = "Crowd-control filter", token = "CROWD_CONTROL", effect = "shows crowd-control debuffs such as control or lockout-style effects Blizzard classifies as CC.", bestFor = "PvP, crowd-control tracking, and knowing when a unit is controlled.", caution = "It is usually not the first choice for raid PvE debuff cleanup." },
    },
}

R.AURA_GROUP_FILTER_EFFECTS = {
    ALL = "shows the normal aura set for that group lane without applying an extra live filter token.",
    PLAYER = "shows only auras cast by you, your pet, or your vehicle.",
    RAID = "keeps auras Blizzard marks as raid-frame relevant.",
    RAID_IN_COMBAT = "uses Blizzard's stricter combat-aware raid-frame visibility.",
    INCLUDE_NAME_PLATE_ONLY = "also includes auras Blizzard normally marks for nameplates instead of unit frames.",
    CANCELABLE = "shows buffs that can be canceled by the player.",
    NOT_CANCELABLE = "shows buffs that cannot be canceled by the player.",
    EXTERNAL_DEFENSIVE = "shows defensive cooldowns placed on the unit by someone else.",
    BIG_DEFENSIVE = "shows major defensive buffs Blizzard classifies as big defensives.",
    RAID_PLAYER_DISPELLABLE = "shows debuffs with a dispel type your character can remove.",
    CROWD_CONTROL = "shows crowd-control debuffs.",
}

function R.AuraFilterStatusWantsAnswer(norm)
    if not R.ContainsAny(norm, { "filter", "filters", "dispellable", "raid in combat", "nameplate", "crowd control", "cc", "cancelable", "cancellable", "defensive", "exclusive" }) then return false end
    if R.ContainsAny(norm, {
        "what filter", "which filter", "which filters", "active filter", "active filters", "current filter", "current filters",
        "what does", "what do", "what is", "explain", "explain filters", "explain filter", "how does", "why use",
        "is active", "are active", "is enabled", "are enabled", "is on", "are on",
        "status", "show active", "show me active",
    }) then
        return true
    end
    if R.ContainsAny(norm, { "active", "current", "status" }) and R.ContainsAny(norm, { "filter", "filters" }) then return true end
    if R.ContainsAny(norm, { "what", "which" }) and R.ContainsAny(norm, { "filter", "filters" }) then return true end
    if R.ContainsAny(norm, { "is " }) and R.ContainsAny(norm, { " on", " off", " active", " enabled", " disabled" }) then return true end
    return false
end

function R.AuraFilterKeyFromText(norm)
    if R.ContainsAny(norm, { "exclusive filter", "exclusive" }) then return "exclusive" end
    if R.ContainsAny(norm, { "raid in combat", "combat raid" }) then return "raidInCombat" end
    if R.ContainsAny(norm, { "nameplate only", "nameplate-only", "include nameplate" }) then return "includeNameplateOnly" end
    if R.ContainsAny(norm, { "dispellable", "dispelable", "purgeable" }) then return "includeDispellable" end
    if R.ContainsAny(norm, { "crowd control", "cc debuff", "cc debuffs" }) then return "crowdControl" end
    if R.ContainsAny(norm, { "not cancelable", "not cancellable", "non cancelable", "uncancelable" }) then return "notCancelable" end
    if R.ContainsAny(norm, { "cancelable", "cancellable" }) then return "cancelable" end
    if R.ContainsAny(norm, { "external defensive", "external defensives", "external buffs" }) then return "externalDefensive" end
    if R.ContainsAny(norm, { "big defensive", "big defensives", "major defensive", "major defensives" }) then return "bigDefensive" end
    if R.ContainsAny(norm, { "player filter", "only my", "only mine", "my buffs", "my debuffs", "own buffs", "own debuffs" }) then return "onlyMine" end
    if R.ContainsAny(norm, { "raid filter", "raid buff", "raid buffs", "raid debuff", "raid debuffs" }) then return "raid" end
    return nil
end

function R.AuraFilterLaneForKey(key, lane)
    if lane then return lane end
    if key == "includeDispellable" or key == "crowdControl" then return "debuff" end
    if key == "cancelable" or key == "notCancelable" or key == "externalDefensive" or key == "bigDefensive" then return "buff" end
    return nil
end

function R.AuraFilterScopeFromText(norm)
    if R.ContainsAny(norm, { "shared", "global", "shared aura", "shared auras", "all unit auras" }) then return "shared", "Shared", false end
    local groupScope, groupLabel = R.GroupScopeFromText(norm)
    local unit, unitLabel = R.UnitScopeFromText(norm)
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit, unitLabel, false end
    if groupScope then return groupScope, groupLabel, true end
    return nil, nil, false
end

function R.AuraReadSettingValue(key)
    local registry = A.Registry
    local setting = registry and type(registry.GetSetting) == "function" and registry:GetSetting(key) or nil
    if not setting or type(setting.get) ~= "function" then return nil, setting end
    local ok, value = pcall(setting.get)
    if ok then return value, setting end
    return nil, setting
end

function R.AuraFilterEffectSentence(text)
    text = tostring(text or "")
    if text == "" then return text end
    return text:gsub("^%l", string.upper)
end

function R.AuraFilterSpecLines(spec, stateLine)
    local lines = {}
    if stateLine and stateLine ~= "" then lines[#lines + 1] = stateLine end
    if spec and spec.effect then lines[#lines + 1] = "Plain English: " .. R.AuraFilterEffectSentence(spec.effect) end
    if spec and spec.bestFor then lines[#lines + 1] = "Good when: " .. R.AuraFilterEffectSentence(spec.bestFor) end
    if spec and spec.caution then lines[#lines + 1] = "Careful: " .. R.AuraFilterEffectSentence(spec.caution) end
    if spec and spec.token then lines[#lines + 1] = "Blizzard token MSUF sends to the native AuraContainer: " .. tostring(spec.token) .. "." end
    return lines
end

function R.AuraFilterBoolSpec(lane, key)
    local specs = R.AURA_UNIT_FILTER_SPECS[lane] or {}
    for i = 1, #specs do
        if specs[i].key == key then return specs[i] end
    end
    return nil
end

function R.AuraFilterTokenList(scope, lane, filtersEnabled)
    local tokens = { lane == "buff" and "HELPFUL" or "HARMFUL" }
    if filtersEnabled == false then return tokens end
    local exclusive = R.AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter.exclusive")
    if tostring(exclusive or "none") == "raid" then tokens[#tokens + 1] = "RAID" end
    local specs = R.AURA_UNIT_FILTER_SPECS[lane] or {}
    for i = 1, #specs do
        local spec = specs[i]
        if spec.token and R.AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(spec.key)) == true then
            local seen = false
            for j = 1, #tokens do if tokens[j] == spec.token then seen = true break end end
            if not seen then tokens[#tokens + 1] = spec.token end
        end
    end
    return tokens
end

function R.AuraExclusiveFilterLine(scope, scopeLabel, lane)
    local value = R.AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter.exclusive")
    value = tostring(value or "none")
    local active = value ~= "" and value ~= "none"
    if active then
        return "Exclusive filter is active: " .. tostring(A.HumanizeDisplayKey and A.HumanizeDisplayKey(value) or value) .. ". Plain English: MSUF starts from that stricter base list before any other toggles narrow the lane further."
    end
    return "Exclusive filter is none. Plain English: the exclusive dropdown is not adding a hidden extra restriction."
end

function R.AuraFilterRecommendationWantsAnswer(norm)
    norm = R.Normalize(norm)
    if not R.ContainsAny(norm, { "filter", "filters" }) then return false end
    if R.ContainsAny(norm, { "good filter", "best filter", "which filter should", "what filter should", "recommend", "recommendation", "for raid", "for raids", "raid setup", "raiding", "new player", "beginner" }) then
        return true
    end
    return false
end

function R.AuraRaidFilterRecommendationReply(norm)
    local lines = {}
    lines[#lines + 1] = "Raid aura filter recommendation"
    lines[#lines + 1] = "Short answer: start with Raid for general raid relevance, use Raid In Combat when you want less clutter during pulls, and use Dispellable Debuffs if your main job is cleansing."
    lines[#lines + 1] = "For a new player, think of filters as a sieve. The aura lane still exists, but the filter decides which icons are allowed through."
    lines[#lines + 1] = "Good raid starting points:"
    lines[#lines + 1] = "- Raid or Mythic Raid debuffs: set the Debuff filter to RAID. If the frame is still too noisy, try RAID_IN_COMBAT."
    lines[#lines + 1] = "- Healer dispels: use RAID_PLAYER_DISPELLABLE on debuffs when you only want debuffs your character can remove."
    lines[#lines + 1] = "- DPS personal tracking: use PLAYER on target debuffs when you only care about your own DoTs."
    lines[#lines + 1] = "- Defensive cooldown tracking: use BIG_DEFENSIVE for major defensives, or EXTERNAL_DEFENSIVE when you want externals on a unit."
    lines[#lines + 1] = "I would not start with Include Nameplate-only. Use that only when you know a specific aura appears on nameplates but is missing from MSUF."
    lines[#lines + 1] = "MSUF detail: Player/Target/Focus/Boss use separate filter toggles. Party/Raid/Mythic Raid use one live dropdown token per Buff or Debuff lane."
    lines[#lines + 1] = "Examples: set raid debuff filter to RAID; set raid debuff filter to RAID_IN_COMBAT; set raid debuff filter to RAID_PLAYER_DISPELLABLE; turn on target debuff player filter."
    return {
        kind = "answer",
        status = "info",
        result = "info",
        text = table.concat(lines, "\n"),
        summary = "Recommends beginner-friendly aura filters for raid use.",
        searchResults = R.PageFollowupResults and R.PageFollowupResults("auras3_filters", "Aura Filters", "Aura filter recommendations live in Aura Filters.") or nil,
    }
end

function R.AuraFilterOverviewReply(norm)
    local lines = {}
    lines[#lines + 1] = "Aura filters, in normal words"
    lines[#lines + 1] = "Filters do not move icons or resize them. They decide which Buff or Debuff icons are allowed to show."
    lines[#lines + 1] = "Common choices:"
    lines[#lines + 1] = "- ALL: no extra narrowing on group frames."
    lines[#lines + 1] = "- PLAYER: only your own buffs/debuffs. Good for tracking your DoTs or HoTs."
    lines[#lines + 1] = "- RAID: Blizzard's raid-frame relevant list. Good default for raids."
    lines[#lines + 1] = "- RAID_IN_COMBAT: stricter raid list while fighting. Good when raid frames are too noisy."
    lines[#lines + 1] = "- RAID_PLAYER_DISPELLABLE: debuffs your character can dispel. Good for healers."
    lines[#lines + 1] = "- BIG_DEFENSIVE / EXTERNAL_DEFENSIVE: defensive cooldown tracking."
    lines[#lines + 1] = "- CROWD_CONTROL: CC effects, usually more useful in PvP or control-heavy situations."
    lines[#lines + 1] = "To read the exact active state I need the frame and lane, for example Target Debuffs, Player Buffs, Raid Debuffs, or Party Buffs."
    lines[#lines + 1] = "Examples: what active target debuff filters do I have; explain party buff filters; what is a good filter for raid."
    return {
        kind = "answer",
        status = "info",
        result = "info",
        text = table.concat(lines, "\n"),
        summary = "Explains aura filters for beginners.",
        searchResults = R.PageFollowupResults and R.PageFollowupResults("auras3_filters", "Aura Filters", "Aura filters live on the Aura Filters page.") or nil,
    }
end

function R.AuraUnitFilterStatusReply(norm, scope, scopeLabel, lane, laneLabel, requestedKey)
    local filtersEnabled = R.AuraReadSettingValue("auras3." .. tostring(scope) .. ".filtersEnabled")
    if filtersEnabled == nil then filtersEnabled = true end

    local lines = {}
    lines[#lines + 1] = scopeLabel .. " " .. laneLabel .. " filters"
    lines[#lines + 1] = "Plain English: this controls which " .. laneLabel:lower() .. " icons MSUF lets through on " .. scopeLabel .. ". It does not change icon size or position."
    lines[#lines + 1] = filtersEnabled and "Filter gate: enabled. The active toggles below affect the live native AuraContainer." or "Filter gate: disabled. The lane can still show auras, but these filter toggles will not narrow it until filters are enabled."

    if requestedKey and requestedKey ~= "exclusive" then
        local spec = R.AuraFilterBoolSpec(lane, requestedKey)
        if spec then
            local value = R.AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(spec.key))
            local active = value == true and filtersEnabled ~= false
            local stateLine = spec.label .. " is " .. (active and "active" or "inactive") .. "."
            local specLines = R.AuraFilterSpecLines(spec, stateLine)
            for i = 1, #specLines do lines[#lines + 1] = specLines[i] end
        end
    elseif requestedKey == "exclusive" then
        lines[#lines + 1] = R.AuraExclusiveFilterLine(scope, scopeLabel, lane)
    else
        local active = {}
        local specs = R.AURA_UNIT_FILTER_SPECS[lane] or {}
        for i = 1, #specs do
            local spec = specs[i]
            local value = R.AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(spec.key))
            if value == true then active[#active + 1] = spec.label .. ": " .. R.AuraFilterEffectSentence(spec.effect) end
        end
        lines[#lines + 1] = R.AuraExclusiveFilterLine(scope, scopeLabel, lane)
        if #active == 0 then
            lines[#lines + 1] = "Active filters right now: none. That means this lane is not being narrowed by MSUF's live filter toggles."
            if lane == "debuff" then
                lines[#lines + 1] = "Beginner tip: for raid debuffs, Raid is the normal first filter; Dispellable is the healer-cleanse view; Player is only your own debuffs."
            else
                lines[#lines + 1] = "Beginner tip: for raid buffs, Raid is the normal clean view; Big Defensive and External Defensive are specialized cooldown-tracking views."
            end
        else
            lines[#lines + 1] = "Active filters right now:"
            for i = 1, #active do lines[#lines + 1] = "- " .. active[i] end
        end
    end

    local tokens = R.AuraFilterTokenList(scope, lane, filtersEnabled)
    lines[#lines + 1] = "Native filter string MSUF builds from this: " .. table.concat(tokens, "|") .. "."
    lines[#lines + 1] = "Safe next commands: 'turn on " .. tostring(scope) .. " " .. tostring(lane) .. " raid filter', 'turn off " .. tostring(scope) .. " " .. tostring(lane) .. " player filter', or 'set " .. tostring(scope) .. " " .. tostring(lane) .. " exclusive filter to none'."
    local reply = {
        kind = "answer",
        status = "info",
        result = "info",
        text = table.concat(lines, "\n"),
        summary = "Explains active unit aura filters.",
        searchResults = R.SettingFollowupResultsByQuery(scopeLabel .. " " .. laneLabel .. " filters", scopeLabel .. " " .. laneLabel .. " Filters"),
    }
    return reply
end

function R.AuraGroupFilterStatusReply(norm, scope, scopeLabel, lane, laneLabel, requestedKey)
    local rootEnabled = R.AuraReadSettingValue("gf_" .. tostring(scope) .. ".auras.enabled")
    local laneEnabled = R.AuraReadSettingValue("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled")
    local token, tokenSetting = R.AuraReadSettingValue("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".filterToken")
    token = tostring(token or "ALL")
    local tokenLabel = tokenSetting and R.RegistryValueLabel(tokenSetting, token) or (A.HumanizeDisplayKey and A.HumanizeDisplayKey(token) or token)
    local effect = R.AURA_GROUP_FILTER_EFFECTS[token] or "uses that group aura filter token for the lane."

    local lines = {}
    lines[#lines + 1] = scopeLabel .. " " .. laneLabel .. " group aura filter"
    lines[#lines + 1] = "Plain English: group-frame aura filters are a single dropdown per lane. Pick one main job for the lane: all auras, your auras, raid-relevant auras, dispellable debuffs, defensive buffs, or crowd control."
    lines[#lines + 1] = (rootEnabled == false) and "Group Auras are disabled for this scope, so this filter will not be visible until Group Auras are enabled." or "Group Auras are enabled or using their default enabled state."
    lines[#lines + 1] = (laneEnabled == false) and laneLabel .. " lane is disabled, so the filter cannot show icons yet." or laneLabel .. " lane is enabled or using its default enabled state."
    lines[#lines + 1] = "Current live filter token: " .. tostring(tokenLabel) .. ". Plain English: it " .. effect
    if token == "ALL" then
        lines[#lines + 1] = "That means the group lane is not currently narrowed by the live group filter dropdown."
    else
        lines[#lines + 1] = "That means normal auras outside this token may be hidden even when the lane itself is enabled."
    end
    if lane == "debuff" then
        lines[#lines + 1] = "Raid beginner tip: RAID is the usual first pick, RAID_IN_COMBAT is cleaner during pulls, and RAID_PLAYER_DISPELLABLE is the healer-cleanse view."
    else
        lines[#lines + 1] = "Raid beginner tip: RAID is the usual clean buff view; BIG_DEFENSIVE and EXTERNAL_DEFENSIVE are for defensive cooldown tracking."
    end
    lines[#lines + 1] = "Safe next commands: 'set " .. tostring(scope) .. " " .. tostring(lane) .. " filter to RAID', 'set " .. tostring(scope) .. " " .. tostring(lane) .. " filter to RAID_IN_COMBAT', or 'set " .. tostring(scope) .. " " .. tostring(lane) .. " filter to ALL'."

    return {
        kind = "answer",
        status = "info",
        result = "info",
        text = table.concat(lines, "\n"),
        summary = "Explains active group aura filter.",
        searchResults = R.SettingFollowupResults("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".filterToken", scopeLabel .. " " .. laneLabel .. " filter"),
    }
end

A.RouterTryAuraFilterStatusShortcut = function(norm)
    norm = R.Normalize(norm)
    if not R.AuraFilterStatusWantsAnswer(norm) then return nil end

    if R.AuraFilterRecommendationWantsAnswer(norm) then
        return R.AuraRaidFilterRecommendationReply(norm)
    end

    local requestedKey = R.AuraFilterKeyFromText(norm)
    local lane, laneLabel = R.AuraLaneFromText(norm)
    lane = R.AuraFilterLaneForKey(requestedKey, lane)
    if lane and not laneLabel then laneLabel = lane == "buff" and "Buff" or "Debuff" end

    local scope, scopeLabel, isGroupScope = R.AuraFilterScopeFromText(norm)
    if requestedKey and not scope then
        local effect
        if requestedKey == "exclusive" then
            effect = "Exclusive filters are stricter lane filters. 'none' means no exclusive restriction; debuff lanes can use raid/encounter style exclusive filtering where supported."
        else
            local buffSpec = R.AuraFilterBoolSpec("buff", requestedKey)
            local debuffSpec = R.AuraFilterBoolSpec("debuff", requestedKey)
            local spec = debuffSpec or buffSpec
            if spec then
                local detail = R.AuraFilterSpecLines(spec)
                effect = table.concat(detail, "\n")
            end
        end
        if effect then
            return A.RouterAuraProblemReply(
                "Aura filter explanation",
                R.AuraFilterEffectSentence(effect) .. "\nTo tell you whether it is active, name the scope and lane, for example Target Debuffs or Party Buffs.",
                "what active target debuff filters do I have; is player buff raid filter on; set target debuff dispellable filter on.",
                "Open Aura Filters | Check Target Debuffs"
            )
        end
    end

    if not scope or not lane then
        return R.AuraFilterOverviewReply(norm)
    end

    if isGroupScope then
        return R.AuraGroupFilterStatusReply(norm, scope, scopeLabel, lane, laneLabel or (lane == "buff" and "Buff" or "Debuff"), requestedKey)
    end
    return R.AuraUnitFilterStatusReply(norm, scope, scopeLabel, lane, laneLabel or (lane == "buff" and "Buff" or "Debuff"), requestedKey)
end

A.RouterTryAuraProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    local terms = A.RouterAuraProblemTerms
    if R.ContainsAny(norm, terms.masque) then
        local reply = A.RouterAuraProblemReply(
            "Masque aura skinning",
            "I will not toggle Masque from the Assistant because this MSUF build does not expose a live Masque aura-skinning path in the active menu or renderer. Use the Masque addon itself for skin selection if it is installed. In MSUF, I can still change aura icon size, caps, borders, cooldown text, stack text, duration bars, and live filters.",
            "open auras; set target buff icon size to 30; set aura cooldown text size to 14; open aura style.",
            "Open Auras | Open Aura Style | Open Aura Filters"
        )
        reply.status = "info"
        reply.result = "info"
        return reply
    end
    local mentionsAura = R.ContainsAny(norm, terms.aura)
        or R.ContainsAny(norm, terms.filter)
        or R.ContainsAny(norm, terms.text)
        or R.AuraSpecificSpellRequest(norm)
    if not mentionsAura then return nil end

    local filterStatusResult = A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(norm)
    if filterStatusResult then return filterStatusResult end

    local detailSettingResult = A.RouterTryAuraDetailSettingShortcut and A.RouterTryAuraDetailSettingShortcut(norm, coreHandler)
    if detailSettingResult then return detailSettingResult end

    local naturalSettingResult = A.RouterTryAuraSettingShortcut and A.RouterTryAuraSettingShortcut(norm, coreHandler)
    if naturalSettingResult then return naturalSettingResult end

    if R.AsksSettingLocation(norm) and R.ContainsAny(norm, terms.text) then
        local unit, unitLabel = R.UnitScopeFromText(norm)
        local groupScope, groupLabel = R.GroupScopeFromText(norm)
        local scope = groupScope or unit or "target"
        local scopeLabel = groupLabel or unitLabel or "Target"
        local textLabel = R.ContainsAny(norm, { "stack text", "stack count", "count text" }) and "Stack Text" or "Cooldown Text"
        local page = groupScope and "Group Auras" or "Aura Style"
        local pageBody = groupScope and (page .. " and Aura Style") or "Aura Style"
        local reply = A.RouterAuraProblemReply(
            scopeLabel .. " Aura " .. textLabel .. " setting location",
            scopeLabel .. " aura " .. textLabel .. " controls live in " .. pageBody .. ". Use cooldown/stack text visibility, font size, color, anchor, and offset controls there; lane-specific Buff/Debuff pages still control which icons are shown.",
            "open aura style; set target buff cooldown text size to 14; show target buff stack text.",
            "Open Aura Style | Open Auras | Open Aura Filters"
        )
        reply.status = "applied"
        reply.result = "applied"
        return reply
    end

    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.HasNaturalProblemTerm(norm)
        and not R.ContainsAny(norm, terms.layout)
        and not R.ContainsAny(norm, terms.filter)
    then
        return nil
    end

    if R.ContainsAny(norm, terms.filter) then
        return A.RouterAuraProblemReply(
            "Aura filter help",
            "Aura filters depend on the exact scope and lane: unit buffs, unit debuffs, group buffs, or group debuffs. Use Aura Editing Scope, Aura Filter Lane, live filter tokens, and quick presets before applying a new filter. Saved exact SpellID blacklist/category data is read-only in the native 12.1 backend.",
            "open aura filters; set aura editing scope to target; set target debuff dispellable filter on; check target buffs.",
            "Open Aura Filters | Open Auras | Check target buffs | Open Group Auras"
        )
    end

    if R.ContainsAny(norm, terms.layout) then
        return A.RouterAuraProblemReply(
            "Aura layout help",
            "Aura position, side, growth direction, anchor, icon count, and offsets are scoped by frame and lane. Name the exact frame and buff/debuff lane when you want me to change it.",
            "set target debuffs grow down; set target buff anchor to top right; open auras.",
            "Open Auras | Open Group Auras | Check target buffs"
        )
    end

    if R.ContainsAny(norm, terms.text) and R.HasNaturalProblemTerm(norm) then
        return A.RouterAuraProblemReply(
            "Aura text visibility help",
            "Aura cooldown and stack text are separate from normal frame text. If they are missing, check aura cooldown text, stack text, font size, color, and lane-specific aura visibility for the affected frame.",
            "set target buff cooldown text size to 14; show target buff stack text; open auras.",
            "Open Auras | Open Aura Filters | Check target buffs"
        )
    end

    return nil
end

A.RouterCastbarProblemTerms = A.RouterCastbarProblemTerms or {
    castbar = {
        "castbar", "castbars", "cast bar", "cast bars", "casting bar",
        "player cast", "target cast", "focus cast", "boss cast",
        "cast color", "cast colours", "cast colors", "interruptible", "uninterruptible",
        "non interruptible", "noninterruptible", "focus kick", "kick tracker", "interrupt tracker",
    },
    position = {
        "wrong place", "wrong position", "position is wrong", "anchor is wrong",
        "offset is wrong", "offset wrong", "off screen", "stuck", "not moving",
        "does not move", "doesn't move", "cannot move", "can't move", "cant move",
    },
    preview = {
        "preview", "test cast", "test mode",
    },
    part = {
        "icon", "timer", "time text", "timer text", "cast text", "spell text",
    },
    broken = {
        "not working", "does not work", "doesn't work", "broken", "not showing",
        "missing", "hidden", "gone",
    },
}

A.RouterCastbarProblemReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Cast bar help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open cast bars; check target cast bar.") .. "\nYou can ask: " .. tostring(actions or "Open Cast Bars | Check target cast bar"),
        status = "info",
        summary = "Assistant cast bar help",
    }
end

function R.CastbarUnitFromText(norm)
    local unit, label = R.UnitScopeFromText(norm)
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit, label end
    return nil, nil
end

function R.UnsupportedCastbarUnitFromText(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, { "target of target", "targettarget", "tot" }) then
        return "targettarget", "Target of Target", "Target"
    end
    if R.ContainsAny(norm, { "focus target", "focustarget" }) then
        return "focustarget", "Focus Target", "Focus"
    end
    return nil, nil, nil
end

function A.RouterTryUnsupportedUnitCastbarShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if not R.ContainsAny(norm, { "castbar", "castbars", "cast bar", "cast bars", "casting bar" }) then return nil end
    local unit, unitLabel, fallbackUnitLabel = R.UnsupportedCastbarUnitFromText(norm)
    if not unit then return nil end
    local asksLocation = R.AsksSettingLocation(norm)
    local wantsChange = R.ContainsAny(norm, {
        "show", "hide", "enable", "disable", "turn on", "turn off", "make visible", "visible",
        "anzeigen", "ausblenden", "einblenden", "aktivieren", "deaktivieren",
    })
    if not asksLocation and not wantsChange and not R.HasNaturalProblemTerm(norm) then return nil end

    local reply = A.RouterCastbarProblemReply(
        unitLabel .. " cast bar help",
        unitLabel .. " does not have its own separate cast bar toggle in MSUF. Cast bar controls are available for Player, Target, Focus, and Boss. For " .. unitLabel .. " readability, use its normal frame options, or tune the " .. fallbackUnitLabel .. " cast bar when that is the cast signal you want to see.",
        "open " .. unitLabel:lower() .. "; open cast bars; show " .. fallbackUnitLabel:lower() .. " cast bar; set " .. fallbackUnitLabel:lower() .. " cast bar height to 24.",
        "Open " .. unitLabel .. " | Open Cast Bars | show " .. fallbackUnitLabel:lower() .. " cast bar"
    )
    reply.status = asksLocation and "applied" or "info"
    reply.result = reply.status
    return reply
end

function R.CastbarSettingFromText(norm)
    if R.ContainsAny(norm, { "icon", "spell icon", "cast icon", "castbar icon", "cast bar icon" }) then
        return "icon", "Castbar Icon", "castbar icon"
    end
    if R.ContainsAny(norm, { "time", "timer", "time text", "timer text", "cast time" }) then
        return "time", "Cast Time Text", "cast time"
    end
    if R.ContainsAny(norm, { "text", "spell text", "spell name", "cast text" }) then
        return "text", "Castbar Spell Text", "castbar text"
    end
    if R.ContainsAny(norm, { "width", "wider", "wide" }) then return "width", "Castbar Width", "castbar width" end
    if R.ContainsAny(norm, { "height", "taller", "high" }) then return "height", "Castbar Height", "castbar height" end
    if R.ContainsAny(norm, { "position", "move", "anchor", "offset", "x offset", "y offset", "wrong place" }) then
        return "position", "Castbar Position", "castbar position"
    end
    return "visibility", "Cast Bar", "castbar"
end

A.RouterTryCastbarSpecialSettingShortcut = function(norm, coreHandler)
    local asksLocation = R.AsksSettingLocation(norm)
    if not asksLocation then return nil end

    if R.ContainsAny(norm, { "focus kick", "kick tracker", "focus interrupt tracker", "interrupt tracker" }) then
        local settingLabel = "Focus Kick Tracker"
        local command = "show focus kick tracker"
        if R.ContainsAny(norm, { "width", "wider", "bigger", "larger", "size" }) then
            settingLabel = "Focus Kick Width"
            command = "set focus kick width to 48"
        elseif R.ContainsAny(norm, { "height", "taller" }) then
            settingLabel = "Focus Kick Height"
            command = "set focus kick height to 48"
        elseif R.ContainsAny(norm, { "text", "font" }) then
            settingLabel = "Focus Kick Text Size"
            command = "set focus kick text size to 14"
        elseif R.ContainsAny(norm, { "move", "position", "offset", "x offset", "y offset" }) then
            settingLabel = "Focus Kick Position"
            command = "move focus kick tracker left 10"
        end
        local reply = A.RouterCastbarProblemReply(
            settingLabel .. " setting location",
            settingLabel .. " lives in Cast Bars under the Focus Kick Tracker controls. Use its visibility, preview, width, height, text size, X offset, and Y offset options there.",
            "open cast bars; " .. command .. "; reset focus kick position.",
            "Open Cast Bars | " .. command
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
            or R.PageFollowupResults("opt_castbar", "Cast Bars", "Focus Kick Tracker controls live in Cast Bars.")
        return reply
    end

    if R.ContainsAny(norm, { "interruptible color", "interruptible cast color", "uninterruptible color", "uninterruptible cast color", "non interruptible color", "non interruptible cast color", "noninterruptible cast color", "castbar interrupt color", "cast bar interrupt color", "kickable cast color", "unkickable cast color" }) then
        local settingLabel = R.ContainsAny(norm, { "uninterruptible", "non interruptible", "noninterruptible", "unkickable", "not kickable" })
            and "Non-Interruptible Cast Color"
            or "Interruptible Cast Color"
        local command = settingLabel == "Non-Interruptible Cast Color" and "set uninterruptible cast color to red" or "set interruptible cast color to blue"
        local reply = A.RouterCastbarProblemReply(
            settingLabel .. " setting location",
            "Cast Bar interrupt color help: " .. settingLabel .. " lives in Colors/Cast Bars as a global cast-bar color option. It controls the color used for casts that are " .. (settingLabel == "Non-Interruptible Cast Color" and "not interruptible" or "interruptible") .. "; it is separate from the Interrupt Ready indicator.",
            "open cast bars; open colors; " .. command .. ".",
            "Open Cast Bars | Open Colors | " .. command
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
            or R.PageFollowupResults("opt_castbar", "Cast Bars", "Cast bar interrupt color controls live in Cast Bars and Colors.")
        return reply
    end

    return nil
end

A.RouterTryCastbarSettingShortcut = function(norm, coreHandler)
    local asksLocation = R.AsksSettingLocation(norm)
    if not asksLocation then return nil end
    if R.ContainsAny(norm, {
        "font size", "text size", "spell name font", "spell name size",
        "spell text size", "castbar spell name font size", "cast bar spell name font size",
    }) then
        return nil
    end
    local specialResult = A.RouterTryCastbarSpecialSettingShortcut and A.RouterTryCastbarSpecialSettingShortcut(norm, coreHandler)
    if specialResult then return specialResult end
    local unit, unitLabel = R.CastbarUnitFromText(norm)
    if not unit then return nil end
    local key, settingLabel, commandNoun = R.CastbarSettingFromText(norm)
    local title = unitLabel .. " " .. settingLabel .. " setting location"
    local body = unitLabel .. " " .. settingLabel .. " lives in Cast Bars. Open Cast Bars and use " .. unitLabel .. " " .. settingLabel .. "."
    if key == "position" then
        body = unitLabel .. " cast bar placement lives in Cast Bars and MSUF Edit Mode. Use " .. unitLabel .. " Castbar X/Y, anchors, or Edit Mode before changing unrelated frame size."
    end
    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm)
    if asksLocation and R.IsDisplayOnlySettingsRequest(norm) then
        wantsOff, wantsOn = false, false
    end
    local verb = wantsOff and "turn off " or (wantsOn and "turn on " or "set ")
    local example = (key == "width" or key == "height") and ("set " .. unit .. " " .. commandNoun .. " to 24")
        or (verb .. unit .. " " .. commandNoun)
    local reply = A.RouterCastbarProblemReply(
        title,
        body,
        example .. "; open cast bars; check " .. unit .. " cast bar.",
        "Open Cast Bars | " .. example
    )
    reply.status = "applied"
    reply.result = "applied"
    if key == "position" then
        reply.searchResults = R.PageFollowupResults("opt_castbar", "Cast Bars", unitLabel .. " cast bar position is controlled by Cast Bars placement settings and MSUF Edit Mode.")
    else
        reply.searchResults = R.SettingFollowupResultsByQuery(unitLabel .. " " .. settingLabel, unitLabel .. " " .. settingLabel)
            or R.PageFollowupResults("opt_castbar", "Cast Bars", unitLabel .. " " .. settingLabel .. " lives in Cast Bars.")
    end
    return reply
end

A.RouterTryCastbarProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    local terms = A.RouterCastbarProblemTerms
    if not R.ContainsAny(norm, terms.castbar) then return nil end

    local unsupportedUnitCastbarResult = A.RouterTryUnsupportedUnitCastbarShortcut and A.RouterTryUnsupportedUnitCastbarShortcut(text, coreHandler)
    if unsupportedUnitCastbarResult then return unsupportedUnitCastbarResult end

    local specialSettingResult = A.RouterTryCastbarSpecialSettingShortcut and A.RouterTryCastbarSpecialSettingShortcut(norm, coreHandler)
    if specialSettingResult then return specialSettingResult end

    local naturalSettingResult = A.RouterTryCastbarSettingShortcut and A.RouterTryCastbarSettingShortcut(norm, coreHandler)
    if naturalSettingResult then return naturalSettingResult end

    if R.AsksSettingLocation(norm) and R.ContainsAny(norm, {
        "font size", "text size", "spell name font", "spell name size",
        "spell text size", "castbar spell name font size", "cast bar spell name font size",
    }) then
        local registryResult = A.RouterTryRegistrySettingLocationShortcut and A.RouterTryRegistrySettingLocationShortcut(text, coreHandler)
        if registryResult then return registryResult end
    end

    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.HasNaturalProblemTerm(norm)
        and not R.ContainsAny(norm, terms.position)
        and not R.ContainsAny(norm, terms.broken)
    then
        return nil
    end

    if R.ContainsAny(norm, terms.preview) and R.ContainsAny(norm, terms.broken) then
        return A.RouterCastbarProblemReply(
            "Cast bar preview help",
            "Cast bar previews are controlled in Cast Bars and MSUF Edit Mode. If preview or test casts do not appear, check the relevant cast bar visibility first, then use preview controls out of combat.",
            "preview target cast bar; preview boss cast bar; open cast bars; enter edit mode.",
            "Open Cast Bars | Enter Edit Mode | Check target cast bar"
        )
    end

    if R.ContainsAny(norm, terms.position) then
        return A.RouterCastbarProblemReply(
            "Cast bar position help",
            "Cast bar position depends on the unit cast bar, detached/anchored placement options, and MSUF Edit Mode. I should not guess a new position from a problem report; name the unit and direction if you want a concrete move.",
            "open cast bars; enter edit mode; move target cast bar down 10; check target cast bar.",
            "Open Cast Bars | Enter Edit Mode | Check target cast bar"
        )
    end

    if R.ContainsAny(norm, terms.part) and R.HasNaturalProblemTerm(norm) then
        return A.RouterCastbarProblemReply(
            "Cast bar text and icon help",
            "Cast bar icons, timer text, spell text, text size, and icon position are Cast Bar options. If the bar itself is visible but a part is missing, check the unit cast bar text/icon settings before changing size.",
            "show target cast bar icon; set target cast bar text size to 14; open cast bars.",
            "Open Cast Bars | Check target cast bar"
        )
    end

    if R.ContainsAny(norm, terms.broken) or R.HasNaturalProblemTerm(norm) then
        local unit, unitLabel = R.CastbarUnitFromText(norm)
        if not unit then
            unit = R.VisibilityCastbarUnitForText and R.VisibilityCastbarUnitForText(R.VisibilityUnitForText(norm)) or nil
        end
        if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "boss" then unit = "target" end
        unitLabel = unitLabel or (unit == "player" and "Player" or unit == "focus" and "Focus" or unit == "boss" and "Boss" or "Target")
        if type(coreHandler) == "function" then
            local result = coreHandler("diagnose " .. unit .. " castbar")
            if result and not A.RouterIsUnknownResult(result) then return result end
        end
        return A.RouterCastbarProblemReply(
            unitLabel .. " cast bar visibility help",
            unitLabel .. " cast bar visibility depends on the Cast Bars page, the owning unit frame being enabled, the selected MSUF/Blizzard backend, Edit Mode position, and whether that unit is currently casting. I will check those first instead of guessing a setting change from a problem report.",
            "diagnose " .. unit .. " castbar; show " .. unit .. " cast bar; open cast bars.",
            "Check " .. unitLabel .. " cast bar | Open Cast Bars | show " .. unit .. " cast bar"
        )
    end

    return nil
end

A.RouterTextPowerProblemTerms = A.RouterTextPowerProblemTerms or {
    text = {
        "health text", "hp text", "power text", "name text", "status text",
        "frame text", "unit text", "text", "font",
    },
    format = {
        "wrong format", "format is wrong", "format wrong", "shows wrong",
        "wrong value", "wrong numbers", "wrong number", "percent wrong",
        "percentage wrong", "current max wrong",
    },
    powerBar = {
        "power bar", "powerbar", "mana bar", "energy bar", "rage bar",
        "detached power bar", "resource bar",
    },
    position = {
        "wrong place", "wrong position", "position is wrong", "anchor is wrong",
        "offset is wrong", "offset wrong", "off screen", "stuck", "not moving",
        "does not move", "doesn't move", "overlap", "overlaps", "overlapping",
    },
}

A.RouterTextPowerProblemReply = function(title, body, examples, actions)
    if type(A.RouterClearPendingResultsForRoute) == "function" then A.RouterClearPendingResultsForRoute() end
    return {
        text = tostring(title or "Text and power bar help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open player; open fonts; check target power bar.") .. "\nYou can ask: " .. tostring(actions or "Open Player | Open Fonts | Open Bars"),
        status = "info",
        summary = "Assistant text and power bar help",
    }
end

function R.TextSettingFromText(norm)
    if R.ContainsAny(norm, { "name text", "name", "unit name" }) then return "name", "Name Text", "name text" end
    if R.ContainsAny(norm, { "health text", "hp text", "health", "hp" }) then return "health", "Health Text", "health text" end
    if R.ContainsAny(norm, { "power text", "mana text", "energy text", "rage text" }) then return "power", "Power Text", "power text" end
    if R.ContainsAny(norm, { "status text", "dead text", "offline text" }) then return "status", "Status Text", "status text" end
    if R.ContainsAny(norm, { "font", "font size", "text size" }) then return "font", "Font Size", "text font size" end
    return "text", "Frame Text", "text"
end

function R.LooksLikeUnitNameTextRequest(norm)
    norm = R.Normalize(norm)
    if norm == "" or not R.ContainsAny(norm, { "name", "names", "unit name" }) then return false end
    if R.ContainsAny(norm, {
        "castbar", "cast bar", "spell name", "cast name",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "profile", "profiles", "profile name",
        "ellipsis", "no ellipsis", "truncate", "truncation",
    }) then
        return false
    end
    local unit = R.UnitScopeFromText(norm)
    return unit ~= nil
end

function R.TextPowerSettingFollowupResults(unit, unitLabel, textKind, settingLabel)
    unit = tostring(unit or "")
    unitLabel = tostring(unitLabel or "")
    textKind = tostring(textKind or "")
    settingLabel = tostring(settingLabel or "")
    local key
    if textKind == "name" then
        key = unit .. ".showName"
    elseif textKind == "health" then
        key = unit .. ".showHP"
    elseif textKind == "power" then
        key = unit .. ".showPower"
    elseif textKind == "status" then
        key = unit .. ".statusTextEnabled"
    end
    if key and key ~= "." then
        return R.SettingFollowupResults(key, settingLabel) or R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
    end
    if textKind == "font" and unitLabel ~= "" then
        local fontLabel = unitLabel .. " Font Size"
        return R.SettingFollowupResultsByQuery(fontLabel, fontLabel) or R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
    end
    if settingLabel ~= "" then return R.SettingFollowupResultsByQuery(settingLabel, settingLabel) end
    return nil
end

function R.UnitPageFollowupResults(unit, unitLabel, description)
    unit = tostring(unit or "")
    unitLabel = tostring(unitLabel or "")
    local unitPages = {
        player = "uf_player",
        target = "uf_target",
        focus = "uf_focus",
        pet = "uf_pet",
        boss = "uf_boss",
        targettarget = "uf_targettarget",
        focustarget = "uf_focustarget",
    }
    local page = unitPages[unit]
    if not page then return nil end
    local pageLabel = A.DisplayPageLabel and A.DisplayPageLabel(page, unitLabel ~= "" and unitLabel or "MSUF page") or unitLabel
    return {
        {
            kind = "page",
            key = page,
            label = pageLabel or unitLabel or page,
            page = page,
            pageLabel = pageLabel,
            description = description,
            canOpen = true,
            canExplain = true,
        },
    }
end

function R.PageFollowupResults(page, pageLabel, description)
    page = tostring(page or "")
    if page == "" then return nil end
    pageLabel = tostring(pageLabel or "")
    if pageLabel == "" and A.DisplayPageLabel then pageLabel = A.DisplayPageLabel(page, "MSUF page") end
    if pageLabel == "" then pageLabel = "MSUF page" end
    return {
        {
            kind = "page",
            key = page,
            label = pageLabel,
            page = page,
            pageLabel = pageLabel,
            description = description,
            canOpen = true,
            canExplain = true,
        },
    }
end

function R.PowerBarSettingFollowupResults(unit, settingLabel, norm)
    unit = tostring(unit or "")
    settingLabel = tostring(settingLabel or "")
    norm = R.Normalize(norm)
    local key = unit .. ".showPowerBar"
    if R.ContainsAny(norm, { "detach", "detaches", "detached", "separate", "undock", "own bar" })
        or settingLabel:find("Detach Power Bar", 1, true)
    then
        key = unit .. ".powerBarDetached"
    elseif R.ContainsAny(norm, { "x offset", "left", "right" }) then
        key = unit .. ".detachedPowerBarOffsetX"
    elseif R.ContainsAny(norm, { "y offset", "up", "down" }) then
        key = unit .. ".detachedPowerBarOffsetY"
    end
    if key ~= "." then
        return R.SettingFollowupResults(key, settingLabel) or R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
    end
    if settingLabel ~= "" then return R.SettingFollowupResultsByQuery(settingLabel, settingLabel) end
    return nil
end

A.RouterTryTextPowerSettingShortcut = function(norm, coreHandler)
    local asksLocation = R.AsksSettingLocation(norm)
    if not asksLocation then return nil end

    local unit, unitLabel = R.UnitScopeFromText(norm)
    if not unit or not unitLabel then return nil end

    local mentionsPowerBar = R.ContainsAny(norm, A.RouterTextPowerProblemTerms.powerBar)
    if mentionsPowerBar then
        local settingLabel = unitLabel .. " Power Bar"
        if R.ContainsAny(norm, { "detach", "detaches", "detached", "separate", "undock", "own bar" }) then
            settingLabel = unitLabel .. " Detach Power Bar from Frame"
        elseif R.ContainsAny(norm, { "position", "move", "anchor", "offset", "wrong place", "where" }) then
            settingLabel = unitLabel .. " Power Bar Position"
        end
        local bodyPrefix = R.ContainsAny(norm, { "offset", "x offset", "y offset" }) and "Power Bar offset help: " or "Power Bar help: "
        local reply = A.RouterTextPowerProblemReply(
            settingLabel .. " setting location",
            bodyPrefix .. settingLabel .. " lives on the " .. unitLabel .. " page. Open " .. unitLabel .. " and use the power-bar visibility, detach, width, height, anchor, and X/Y offset controls for that unit.",
            "open " .. unit .. "; detach " .. unit .. " power bar; move " .. unit .. " power bar down 8.",
            "Open " .. unitLabel .. " | detach " .. unit .. " power bar"
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.PowerBarSettingFollowupResults(unit, settingLabel, norm)
        return reply
    end

    local textKind, settingKindLabel, commandNoun = R.TextSettingFromText(norm)
    local settingLabel = unitLabel .. " " .. settingKindLabel
    if R.ContainsAny(norm, { "format", "percent", "percentage", "current", "current max", "value" }) then
        settingLabel = settingLabel .. " Format"
    end
    if textKind == "font" then
        local reply = A.RouterTextPowerProblemReply(
            settingLabel .. " setting location",
            "Unit frame text help: " .. unitLabel .. " text font sizes live on the " .. unitLabel .. " page. Use " .. unitLabel .. " Name Font Size, " .. unitLabel .. " HP Font Size, and " .. unitLabel .. " Power Font Size depending on which text line you mean.",
            "open " .. unit .. "; set " .. unit .. " name text size to 14; set " .. unit .. " hp text size to 14.",
            "Open " .. unitLabel .. " | set " .. unit .. " name text size to 14"
        )
        reply.status = "applied"
        reply.result = "applied"
        reply.searchResults = R.TextPowerSettingFollowupResults(unit, unitLabel, textKind, settingLabel)
        return reply
    end
    local reply = A.RouterTextPowerProblemReply(
        settingLabel .. " setting location",
        "Unit frame text help: " .. settingLabel .. " lives on the " .. unitLabel .. " page. Open " .. unitLabel .. " and use the text visibility, slot, format, font size, anchor, and offset controls for that frame.",
        "open " .. unit .. "; " .. ((R.WantsVisibilityOn(norm) and not R.WantsVisibilityOff(norm)) and "turn on " or "turn off ") .. unit .. " " .. commandNoun .. "; set " .. unit .. " " .. commandNoun .. " size to 14.",
        "Open " .. unitLabel .. " | " .. ((R.WantsVisibilityOn(norm) and not R.WantsVisibilityOff(norm)) and "turn on " or "turn off ") .. unit .. " " .. commandNoun
    )
    reply.status = "applied"
    reply.result = "applied"
    if not R.ContainsAny(norm, { "format", "percent", "percentage", "current", "current max", "value" }) then
        reply.searchResults = R.TextPowerSettingFollowupResults(unit, unitLabel, textKind, settingLabel)
    else
        reply.searchResults = R.UnitPageFollowupResults(unit, unitLabel, "Text format is configured through text slots and related text controls on this unit page.")
    end
    return reply
end

A.RouterTryTextPowerProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    local terms = A.RouterTextPowerProblemTerms
    local mentionsText = R.ContainsAny(norm, terms.text) or R.LooksLikeUnitNameTextRequest(norm)
    local mentionsPowerBar = R.ContainsAny(norm, terms.powerBar)
    if not mentionsText and not mentionsPowerBar then return nil end

    local settingResult = A.RouterTryTextPowerSettingShortcut and A.RouterTryTextPowerSettingShortcut(norm, coreHandler)
    if settingResult then return settingResult end

    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.HasNaturalProblemTerm(norm)
        and not R.ContainsAny(norm, terms.format)
        and not R.ContainsAny(norm, terms.position)
    then
        return nil
    end

    if mentionsText and R.ContainsAny(norm, terms.format) then
        return A.RouterTextPowerProblemReply(
            "Text format help",
            "Unit-frame text format is controlled by the text slot and format options for the specific frame. Group-frame text lives in Group Health & Text. Name the frame and text type before I change it, so I do not overwrite the wrong slot.",
            "set target hp text left current; set player health text to percent; open fonts.",
            "Open Fonts | Open Player | Open Target | Open Group Health & Text"
        )
    end

    if mentionsText and R.HasNaturalProblemTerm(norm) then
        return A.RouterTextPowerProblemReply(
            "Text visibility help",
            "If frame text is missing, check whether the specific text element is enabled, whether the slot is empty, and whether font size, color, alpha, or range fade makes it unreadable.",
            "set player name font size to 14; show target health text; open fonts.",
            "Open Fonts | Open Player | Open Target | Open Group Health & Text"
        )
    end

    if mentionsPowerBar and R.ContainsAny(norm, terms.position) then
        return A.RouterTextPowerProblemReply(
            "Power bar position help",
            "Power bar placement depends on whether the bar is attached to the frame or detached. For detached power bars, use width, height, anchor, X offset, and Y offset on the unit-frame page.",
            "open target; move target power bar down 8; attach target power bar to frame.",
            "Open Player | Open Target | Open Bars"
        )
    end

    if mentionsPowerBar and R.HasNaturalProblemTerm(norm) then
        return A.RouterTextPowerProblemReply(
            "Power bar visibility help",
            "Power bars can be hidden by unit visibility, power-bar enable settings, detach settings, opacity, or zero-sized layout. Name the unit if you want me to run the exact check.",
            "check target power bar; check player power bar; open target.",
            "Open Player | Open Target | Open Bars"
        )
    end

    return nil
end

A.RouterUnitFrameProblemTerms = A.RouterUnitFrameProblemTerms or {
    unit = {
        "player frame", "target frame", "focus frame", "pet frame", "boss frame", "boss frames",
        "target of target", "target of target frame", "focus target", "focus target frame",
        "unit frame", "unit frames", "unitframe", "unitframes",
    },
    position = {
        "wrong position", "position is wrong", "wrong place", "not moving",
        "does not move", "doesn't move", "cannot move", "can't move", "cant move",
        "anchor is wrong", "offset is wrong", "offset wrong", "stuck", "off screen",
    },
    size = {
        "wrong size", "size is wrong", "too small", "too big", "too large", "too tiny",
    },
    color = {
        "wrong color", "color is wrong", "color wrong", "wrong colours", "colour is wrong",
        "too faded", "too transparent", "too dark", "too bright", "hard to see",
    },
    portrait = {
        "portrait", "class portrait", "model portrait", "portrait style",
    },
}

A.RouterUnitFrameProblemReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Unit frame help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open player; enter edit mode.") .. "\nYou can ask: " .. tostring(actions or "Open Player | Open Target | Enter Edit Mode"),
        status = "info",
        summary = "Assistant unit frame help",
    }
end

A.RouterTryUnitFrameProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    local terms = A.RouterUnitFrameProblemTerms
    local mentionsUnit = R.ContainsAny(norm, terms.unit)
    local mentionsPortrait = R.ContainsAny(norm, terms.portrait)
    if not mentionsUnit and not mentionsPortrait then return nil end
    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.ContainsAny(norm, terms.position)
        and not R.ContainsAny(norm, terms.size)
        and not R.ContainsAny(norm, terms.color)
        and not R.HasNaturalProblemTerm(norm)
    then
        return nil
    end

    if mentionsPortrait and (R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, { "wrong", "style", "position", "too" })) then
        return A.RouterUnitFrameProblemReply(
            "Portrait help",
            "Portrait visibility, style, side, and keep-visible behavior are configured on the relevant unit-frame page. Name the unit when you want a concrete change, because Player, Target, Focus, Pet, Boss, Target of Target, and Focus Target can differ.",
            "show player portrait; set target portrait position left; open target.",
            "Open Player | Open Target | Open Boss Frames"
        )
    end

    if mentionsUnit and R.ContainsAny(norm, terms.position) then
        return A.RouterUnitFrameProblemReply(
            "Unit frame position help",
            "Unit-frame position is controlled by the frame page, Edit Mode, anchor point, X position, and Y position. I should not guess a new position from a problem report; name a direction or coordinate when you want me to move it.",
            "enter edit mode; move player frame down 10; open target.",
            "Enter Edit Mode | Open Player | Open Target | Open Boss Frames"
        )
    end

    if mentionsUnit and R.ContainsAny(norm, terms.size) then
        return A.RouterUnitFrameProblemReply(
            "Unit frame size help",
            "Unit-frame size is controlled by width, height, scale, and sometimes text or portrait settings. Start with width and height on the relevant frame before changing global UI scale.",
            "set player width to 300; set target height to 45; open player.",
            "Open Player | Open Target | Open Boss Frames"
        )
    end

    if mentionsUnit and R.ContainsAny(norm, terms.color) then
        return A.RouterUnitFrameProblemReply(
            "Unit frame color and opacity help",
            "Unit-frame colors can come from health color mode, class color mode, bar texture, border color, opacity, and range fade. Check the specific frame first, then global Colors or Bars if the issue is shared.",
            "set player border color blue; set target range fade to 40; open colors.",
            "Open Colors | Open Bars | Open Player | Open Target"
        )
    end

    return nil
end

A.RouterIndicatorProblemTerms = A.RouterIndicatorProblemTerms or {
    indicator = {
        "raid marker", "raid marker icon", "role icon", "ready check", "ready check icon",
        "ready check size", "ready check anchor", "ready check indicator", "readycheck", "ready",
        "leader icon", "assistant icon", "master looter icon", "pvp icon", "pvp flag",
        "resting icon", "rested indicator", "combat icon", "status icon",
        "raid target marker", "target marker", "target icon",
        "moon", "moon icon", "moon marker", "moon symbol", "moon mark",
        "skull", "skull icon", "skull marker", "skull symbol", "skull mark",
        "cross", "cross icon", "cross marker", "cross symbol", "cross mark", "x marker", "x icon", "red x", "red cross",
        "square", "square icon", "square marker", "square symbol", "square mark", "blue square",
        "star", "star icon", "star marker", "star symbol", "star mark", "yellow star",
        "circle", "circle icon", "circle marker", "circle symbol", "circle mark", "orange circle",
        "diamond", "diamond icon", "diamond marker", "diamond symbol", "diamond mark", "purple diamond",
        "triangle", "triangle icon", "triangle marker", "triangle symbol", "triangle mark", "green triangle",
        "elite icon", "rare icon", "level indicator", "level icon",
        "incoming rez icon", "incoming resurrection icon", "resurrection icon", "rez icon",
    },
    position = {
        "wrong position", "position is wrong", "wrong place", "anchor is wrong",
        "offset is wrong", "offset wrong", "not moving", "stuck", "off screen",
    },
}

A.RouterTargetedSpellIndicatorTerms = A.RouterTargetedSpellIndicatorTerms or {
    "targeted spell", "targeted spells", "targeted spell indicator", "targeted spell indicators",
    "targeted spell tracker", "targeted spells tracker", "enemy targeted spell", "enemy targeted spells",
    "enemy nameplate cast tracker", "nameplate cast tracker",
}

A.RouterIndicatorProblemReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Indicator help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open group status and indicators; show raid marker on target.") .. "\nYou can ask: " .. tostring(actions or "Open Group Status & Indicators | Open Player | Open Target"),
        status = "info",
        summary = "Assistant indicator help",
    }
end

function R.IndicatorUnitFromText(norm)
    if R.ContainsAny(norm, { "player", "player frame", "my frame" }) then return "player", "Player" end
    if R.ContainsAny(norm, { "target", "target frame" }) then return "target", "Target" end
    if R.ContainsAny(norm, { "focus", "focus frame" }) then return "focus", "Focus" end
    if R.ContainsAny(norm, { "boss", "boss frame", "boss frames" }) then return "boss", "Boss Frames" end
    return nil, nil
end

function R.IndicatorGroupScopeFromText(norm)
    if R.ContainsAny(norm, { "mythic raid", "mythic raid frame", "mythic raid frames" }) then return "mythic raid" end
    if R.ContainsAny(norm, { "raid", "raid frame", "raid frames" }) then return "raid" end
    if R.ContainsAny(norm, { "party", "party frame", "party frames" }) then return "party" end
    return nil
end

function R.IndicatorSettingFromText(norm)
    if R.ContainsAny(norm, R.SIGNAL_RAID_MARKER_TERMS) or R.ContainsAny(norm, { "raid icon", "raid symbol", "raid indicator" }) then
        return "raid marker", "Raid Marker", "unit"
    end
    if R.ContainsAny(norm, { "leader icon", "leader indicator", "assist icon", "assist indicator", "leader assist icon", "leader assist indicator" }) then
        return "leader icon", "Leader/Assist Icon", "unit"
    end
    if R.ContainsAny(norm, { "combat indicator", "combat state indicator", "combat status indicator", "combat icon", "combat state icon", "combat symbol" }) then
        return "combat indicator", "Combat Indicator", "unit"
    end
    if R.ContainsAny(norm, { "rested indicator", "resting indicator", "rested icon", "resting icon", "rested symbol", "resting symbol", "sleep icon", "zzz icon" }) then
        return "rested indicator", "Rested Indicator", "unit"
    end
    if R.ContainsAny(norm, { "pvp flag", "pvp flag indicator", "pvp indicator", "pvp icon", "pvp status", "war mode indicator", "flagged indicator" }) then
        return "pvp icon", "PvP Flag Indicator", "unit"
    end
    if R.ContainsAny(norm, { "elite icon", "rare icon", "elite rare icon" }) then
        return "elite icon", "Elite / Rare Icon", "unit"
    end
    if R.ContainsAny(norm, { "incoming rez indicator", "incoming resurrection indicator", "incoming rez icon", "incoming resurrection icon", "rez icon", "resurrection icon" }) then
        return "incoming rez indicator", "Incoming Rez Indicator", "unit"
    end
    if R.ContainsAny(norm, { "level indicator", "level text", "level icon" }) then
        return "level indicator", "Level Indicator", "unit"
    end
    if R.ContainsAny(norm, { "ready check", "ready check icon", "ready check indicator", "readycheck", "ready icon" }) then
        return "ready check icon", "Ready Check", "group"
    end
    if R.ContainsAny(norm, { "role icon", "role indicator", "tank icon", "healer icon", "dps icon" }) then
        return "role icon", "Role Icon", "group"
    end
    return nil, nil, nil
end

A.RouterTryIndicatorProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    if R.ContainsAny(norm, A.RouterTargetedSpellIndicatorTerms) then
        local groupScope, groupLabel = R.GroupScopeFromText(norm)
        if groupScope and groupScope ~= "party" then
            return A.RouterIndicatorProblemReply(
                "Targeted Spell Indicators are Party-only",
                "MSUF Targeted Spell Indicators track enemy nameplate casts that target party members. They do not have separate Raid or Mythic Raid settings, so I did not change " .. tostring(groupLabel or "that group scope") .. " frames.",
                "open group status and indicators; show party targeted spell indicators; set party targeted spell icon size to 28.",
                "Open Group Status & Indicators | show party targeted spell indicators"
            )
        end
        local wantsInfo = R.AsksSettingLocation(norm)
            or R.HasNaturalProblemTerm(norm)
            or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS)
            or R.ContainsAny(norm, { "help", "explain", "what is", "what are", "how do", "how can" })
        if wantsInfo then
            return A.RouterIndicatorProblemReply(
                "Targeted Spell Indicators help",
                "Party Targeted Spell Indicators live in Group Status & Indicators. They are party-only and show enemy nameplate casts that target party members. Use exact party commands when you want a change.",
                "show party targeted spell indicators; set party targeted spell icon size to 28; set targeted spell mode to always.",
                "Open Group Status & Indicators | show party targeted spell indicators"
            )
        end
    end

    if R.AsksSettingLocation(norm)
        and norm:find("ready check", 1, true)
        and R.ContainsAny(norm, { "size", "bigger", "larger", "smaller", "anchor", "position", "move", "x offset", "y offset", "offset", "layer" })
    then
        local groupScope = R.IndicatorGroupScopeFromText(norm) or "raid"
        local groupLabel = groupScope == "mythic raid" and "Mythic Raid" or (groupScope == "party" and "Party" or "Raid")
        local layoutLabel = R.ContainsAny(norm, { "size", "bigger", "larger", "smaller" }) and "size" or "layout"
        local reply = A.RouterIndicatorProblemReply(
            "Ready Check " .. layoutLabel .. " setting location",
            "Ready Check " .. layoutLabel .. " for " .. groupLabel .. " frames lives in Group Status & Indicators. Use Ready Check size, anchor, X offset, Y offset, and layer controls for that group scope.",
            "open group status and indicators; set " .. groupScope .. " ready check size to 18; set " .. groupScope .. " ready check anchor top right.",
            "Open Group Status & Indicators | set " .. groupScope .. " ready check size to 18"
        )
        reply.status = "applied"
        reply.result = "applied"
        return reply
    end

    if norm:find("ready check", 1, true)
        and (R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS))
    then
        return A.RouterIndicatorProblemReply(
            "Ready Check visibility help",
            "Ready Check visibility for Party, Raid, and Mythic Raid frames lives in Group Status & Indicators. Check the Ready Check toggle first, then size, anchor, layer, and offsets if the icon is enabled but hard to see.",
            "show raid ready check icon; set party ready check size to 18; open group status and indicators.",
            "Open Group Status & Indicators | show raid ready check icon"
        )
    end

    local terms = A.RouterIndicatorProblemTerms
    if not R.ContainsAny(norm, terms.indicator) then return nil end

    local settingNoun, settingLabel, settingScope = R.IndicatorSettingFromText(norm)
    local asksLocation = norm:match("^where%s+") ~= nil
        or norm:match("^which%s+page") ~= nil
        or norm:match("^what%s+page") ~= nil
        or norm:match("^which%s+menu") ~= nil
        or norm:match("^what%s+menu") ~= nil
        or norm:match("^how%s+do%s+i") ~= nil
        or norm:match("^how%s+can%s+i") ~= nil
        or norm:match("^can%s+i") ~= nil
        or norm:match("^is%s+there%s+a%s+way") ~= nil
        or R.ContainsAny(norm, { "help me find", "help me locate", "tell me where", "looking for" })
    local wantsOff = R.ContainsAny(norm, { "turn off", "disable", "hide", "remove", "get rid", "dont show", "do not show" })
    local wantsOn = R.ContainsAny(norm, { "turn on", "enable", "show" })
    local asksPositionLocation = asksLocation and R.ContainsAny(norm, {
        "move", "position", "place", "placement", "anchor", "x offset", "y offset", "offset",
    })
    local asksIndicatorLayoutLocation = asksLocation and R.ContainsAny(norm, {
        "size", "bigger", "larger", "smaller", "anchor", "position", "move", "x offset", "y offset", "offset", "layer",
    })
    if settingNoun and asksPositionLocation and not wantsOff and not wantsOn then
        local unit, page = R.IndicatorUnitFromText(norm)
        local groupScope = R.IndicatorGroupScopeFromText(norm)
        local groupLabel = groupScope == "mythic raid" and "Mythic Raid" or (groupScope == "raid" and "Raid" or (groupScope == "party" and "Party" or nil))
        local reply
        if unit then
            reply = A.RouterIndicatorProblemReply(
                page .. " " .. settingLabel .. " position setting location",
                settingLabel .. " position for the " .. page .. " frame is controlled in that frame's Status Icons settings. Use " .. page .. " " .. settingLabel .. " anchor, X offset, Y offset, layer, and size controls.",
                "open " .. unit .. "; move " .. unit .. " " .. settingNoun .. " up 4; set " .. unit .. " " .. settingNoun .. " anchor top right.",
                "Open " .. page .. " | move " .. unit .. " " .. settingNoun .. " up 4"
            )
        elseif groupScope then
            local commandNoun = settingNoun == "raid marker" and "raid marker icon" or (groupScope .. " " .. settingNoun)
            reply = A.RouterIndicatorProblemReply(
                settingLabel .. " position setting location",
                settingLabel .. " position for " .. groupLabel .. " frames lives in Group Status & Indicators. Use " .. settingLabel .. " X Offset, " .. settingLabel .. " Y Offset, anchor, layer, and size controls for that group scope.",
                "open group status and indicators; move " .. commandNoun .. " up 4; set " .. commandNoun .. " anchor top right.",
                "Open Group Status & Indicators | move " .. commandNoun .. " up 4"
            )
        else
            reply = A.RouterIndicatorProblemReply(
                settingLabel .. " position setting location",
                settingLabel .. " position lives with the relevant frame scope. Unit-frame indicators are in the Status Icons section for Player, Target, Focus, Pet, and Boss pages. Party, Raid, and Mythic Raid indicators live in Group Status & Indicators.",
                "open target; open group status and indicators; move raid " .. settingNoun .. " up 4.",
                "Open Group Status & Indicators | Open Player | Open Target"
            )
        end
        reply.status = "applied"
        reply.result = "applied"
        return reply
    end
    if settingNoun and asksIndicatorLayoutLocation and not wantsOff and not wantsOn then
        local unit, page = R.IndicatorUnitFromText(norm)
        local groupScope = R.IndicatorGroupScopeFromText(norm)
        local groupLabel = groupScope == "mythic raid" and "Mythic Raid" or (groupScope == "raid" and "Raid" or (groupScope == "party" and "Party" or nil))
        local layoutLabel = R.ContainsAny(norm, { "size", "bigger", "larger", "smaller" }) and "size" or "layout"
        local reply
        if unit then
            reply = A.RouterIndicatorProblemReply(
                page .. " " .. settingLabel .. " " .. layoutLabel .. " setting location",
                settingLabel .. " " .. layoutLabel .. " for the " .. page .. " frame is controlled in that frame's Status Icons settings. Use size, anchor, X offset, Y offset, and layer controls where that indicator exposes them.",
                "open " .. unit .. "; set " .. unit .. " " .. settingNoun .. " size to 18; set " .. unit .. " " .. settingNoun .. " anchor top right.",
                "Open " .. page .. " | set " .. unit .. " " .. settingNoun .. " size to 18"
            )
        elseif groupScope then
            reply = A.RouterIndicatorProblemReply(
                settingLabel .. " " .. layoutLabel .. " setting location",
                settingLabel .. " " .. layoutLabel .. " for " .. groupLabel .. " frames lives in Group Status & Indicators. Use size, anchor, X offset, Y offset, and layer controls for that group scope.",
                "open group status and indicators; set " .. groupScope .. " " .. settingNoun .. " size to 18; set " .. groupScope .. " " .. settingNoun .. " anchor top right.",
                "Open Group Status & Indicators | set " .. groupScope .. " " .. settingNoun .. " size to 18"
            )
        else
            reply = A.RouterIndicatorProblemReply(
                settingLabel .. " " .. layoutLabel .. " setting location",
                settingLabel .. " " .. layoutLabel .. " lives with the relevant frame scope. Unit-frame indicators use Status Icons on the unit page; Party, Raid, and Mythic Raid indicators use Group Status & Indicators.",
                "open group status and indicators; open target; set raid " .. settingNoun .. " size to 18.",
                "Open Group Status & Indicators | Open Player | Open Target"
            )
        end
        reply.status = "applied"
        reply.result = "applied"
        return reply
    end
    if settingNoun and (asksLocation or wantsOff or wantsOn) then
        local unit, page = R.IndicatorUnitFromText(norm)
        local groupScope = R.IndicatorGroupScopeFromText(norm)
        if settingScope == "group" or (groupScope and not unit) then
            if asksLocation and not (wantsOff or wantsOn)
                and R.ContainsAny(norm, { "which page", "what page", "which menu", "what menu" })
            then
                local reply = A.RouterIndicatorProblemReply(
                    "Group Status & Indicators help",
                    settingLabel .. " for Party, Raid, and Mythic Raid frames lives in Group Status & Indicators. Open Group Status & Indicators when you want the page, or ask which setting controls it when you want the exact option.",
                    "open group status and indicators; show raid ready check icon; set raid ready check size to 18.",
                    "Open Group Status & Indicators | show raid ready check icon"
                )
                reply.status = "applied"
                reply.result = "applied"
                return reply
            end
            if asksLocation and not (wantsOff or wantsOn) then return nil end
            local scope = groupScope or "group"
            local verb = wantsOff and "turn off " or "turn on "
            if asksLocation then
                local reply = A.RouterIndicatorProblemReply(
                    settingLabel .. " setting location",
                    settingLabel .. " for Party, Raid, and Mythic Raid frames lives in Group Status & Indicators. Open Group Status & Indicators and use the " .. settingLabel .. " controls for the relevant group scope.",
                    verb .. scope .. " " .. settingNoun .. "; open group status and indicators; set " .. scope .. " " .. settingNoun .. " size to 18.",
                    "Open Group Status & Indicators | " .. verb .. scope .. " " .. settingNoun
                )
                reply.status = "applied"
                reply.result = "applied"
                local queryLabel = (groupLabel or scope) .. " " .. settingLabel
                reply.searchResults = R.SettingFollowupResultsByQuery(queryLabel, queryLabel)
                return reply
            end
            return R.CoreControl(
                coreHandler,
                verb .. scope .. " " .. settingNoun,
                settingLabel .. " lives in Group Status & Indicators. Ask: open group status and indicators, or " .. verb .. scope .. " " .. settingNoun .. ".",
                "info"
            )
        end
        if unit then
            local verb = wantsOff and "turn off " or "turn on "
            if asksLocation then
                local reply = A.RouterIndicatorProblemReply(
                    settingLabel .. " setting location",
                    settingLabel .. " is in the Status Icons section for the " .. page .. " frame. Open " .. page .. " and use the setting called " .. page .. " " .. settingLabel .. ".",
                    verb .. unit .. " " .. settingNoun .. "; open " .. unit .. "; set " .. unit .. " " .. settingNoun .. " size to 18.",
                    "Open " .. page .. " | " .. verb .. unit .. " " .. settingNoun
                )
                reply.status = "applied"
                reply.result = "applied"
                reply.searchResults = R.SettingFollowupResultsByQuery(page .. " " .. settingLabel, page .. " " .. settingLabel)
                return reply
            end
            local result = R.CoreControl(
                coreHandler,
                verb .. unit .. " " .. settingNoun,
                settingLabel .. " is in the Status Icons section for the " .. page .. " frame. Ask: open " .. unit .. ", or " .. verb .. unit .. " " .. settingNoun .. ".",
                "info"
            )
            if result then return result end
        end
    end

    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.ContainsAny(norm, terms.position)
        and not R.HasNaturalProblemTerm(norm)
    then
        return nil
    end

    if R.ContainsAny(norm, terms.position) then
        return A.RouterIndicatorProblemReply(
            "Indicator position help",
            "Indicator position is controlled by the relevant unit-frame or Group Status & Indicators settings: anchor, layer, X offset, Y offset, and size. Name the frame or group scope when you want an exact move.",
            "move raid marker icon up 4; set raid role icon anchor top right; open group status and indicators.",
            "Open Group Status & Indicators | Open Player | Open Target"
        )
    end

    if R.HasNaturalProblemTerm(norm) then
        return A.RouterIndicatorProblemReply(
            "Indicator visibility help",
            "Indicator visibility depends on the relevant unit or group scope. Unit-frame indicators live on Player/Target/Focus/Boss pages, while Party/Raid/Mythic Raid indicators live in Group Status & Indicators.",
            "show raid marker on target; show raid ready check icon; show player rested indicator.",
            "Open Group Status & Indicators | Open Player | Open Target | Open Boss Frames"
        )
    end

    return nil
end

A.RouterClassResourceProblemTerms = A.RouterClassResourceProblemTerms or {
    resource = {
        "class resource", "class resources", "class power", "class powers",
        "combo point", "combo points", "holy power", "arcane charge", "arcane charges",
        "soul shard", "soul shards", "chi", "rune", "runes",
    },
    position = {
        "wrong position", "position is wrong", "wrong place", "not moving",
        "does not move", "doesn't move", "cannot move", "can't move", "cant move",
        "anchor is wrong", "offset is wrong", "offset wrong", "stuck", "off screen",
    },
    color = {
        "wrong color", "color is wrong", "color wrong", "wrong colours", "colour is wrong",
        "too dark", "too bright", "hard to see", "too faded",
    },
    preview = {
        "preview not working", "preview does not work", "preview doesn't work",
        "test not working", "test mode not working",
    },
}

A.RouterClassResourceProblemReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Class Resources help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open class resources; check class resources.") .. "\nYou can ask: " .. tostring(actions or "Open Class Resources | Check Class Resources"),
        status = "info",
        summary = "Assistant class resources help",
    }
end

function R.ClassResourceSettingFollowupResults(settingLabel)
    settingLabel = tostring(settingLabel or "")
    if settingLabel == "Class Resource" then
        return R.SettingFollowupResults("bars.showClassPower", settingLabel)
    end
    if settingLabel == "Class Resource Width" then
        return R.SettingFollowupResults("bars.classPowerWidth", settingLabel)
    end
    if settingLabel == "Class Resource Size" then
        return R.SettingFollowupResults("bars.classPowerHeight", "Class Resource Height")
    end
    if settingLabel == "Class Resource Position" then
        return R.PageFollowupResults("classpower", "Class Resources", "Class Resource position is controlled by Class Resources anchor and offset controls.")
    end
    return R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
        or R.PageFollowupResults("classpower", "Class Resources", settingLabel .. " lives on Class Resources.")
end

A.RouterTryClassResourceSettingShortcut = function(norm, coreHandler)
    if not R.AsksSettingLocation(norm) then return nil end

    local label = "Class Resource"
    local noun = "class resources"
    if R.ContainsAny(norm, { "combo point", "combo points" }) then
        label = "Combo Points"
        noun = "combo points"
    elseif R.ContainsAny(norm, { "holy power" }) then
        label = "Holy Power"
        noun = "holy power"
    elseif R.ContainsAny(norm, { "rune", "runes" }) then
        label = "Runes"
        noun = "runes"
    elseif R.ContainsAny(norm, { "soul shard", "soul shards" }) then
        label = "Soul Shards"
        noun = "soul shards"
    elseif R.ContainsAny(norm, { "chi" }) then
        label = "Chi"
        noun = "chi"
    elseif R.ContainsAny(norm, { "arcane charge", "arcane charges" }) then
        label = "Arcane Charges"
        noun = "arcane charges"
    end

    local settingLabel = label
    if R.ContainsAny(norm, { "position", "move", "anchor", "offset", "wrong place" }) then
        settingLabel = label .. " Position"
    elseif R.ContainsAny(norm, { "width", "wider", "narrower" }) then
        settingLabel = "Class Resource Width"
    elseif R.ContainsAny(norm, { "height", "bigger", "larger", "smaller", "size" }) then
        settingLabel = "Class Resource Size"
    elseif R.ContainsAny(norm, { "color", "colour" }) then
        settingLabel = label .. " Color"
    else
        settingLabel = label == "Class Resource" and "Class Resource" or (label .. " Visibility")
    end

    local isCapabilityQuestion = norm:match("^can%s+i%s+") ~= nil
        or norm:match("^is%s+there%s+a%s+way%s+") ~= nil
    local body
    if isCapabilityQuestion then
        body = "Class Resources help: " .. settingLabel .. " lives on Class Resources. Open Class Resources when you want to inspect it, or ask for an exact change when you want me to apply it."
    else
        if type(coreHandler) == "function" then coreHandler("open class resources") end
        body = "Done. Opened Class Resources.\nClass Resources help: " .. settingLabel .. " lives on Class Resources. Open Class Resources and use visibility, width, height, anchor, X/Y offset, color, and preview controls for the resource your class uses."
    end
    local reply = A.RouterClassResourceProblemReply(
        settingLabel .. " setting location",
        body,
        "open class resources; turn off class resources; move class resources down 5; set class resource width to 120.",
        "Open Class Resources | turn off " .. noun
    )
    reply.status = "applied"
    reply.result = "applied"
    reply.searchResults = R.ClassResourceSettingFollowupResults(settingLabel)
    return reply
end

A.RouterTryClassResourceProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    local terms = A.RouterClassResourceProblemTerms
    if not R.ContainsAny(norm, terms.resource) then return nil end

    local settingResult = A.RouterTryClassResourceSettingShortcut and A.RouterTryClassResourceSettingShortcut(norm, coreHandler)
    if settingResult then return settingResult end

    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.ContainsAny(norm, terms.position)
        and not R.ContainsAny(norm, terms.color)
        and not R.ContainsAny(norm, terms.preview)
        and not R.HasNaturalProblemTerm(norm)
    then
        return nil
    end

    if R.ContainsAny(norm, terms.preview) then
        return A.RouterClassResourceProblemReply(
            "Class Resources preview help",
            "Class Resource previews depend on the selected preview class/spec and on whether the resource exists for that class. If preview looks wrong, open Class Resources, start the preview animation, and verify the class/spec preview target.",
            "preview class resource mage arcane; start class resource preview animation; open class resources.",
            "Open Class Resources | Check Class Resources"
        )
    end

    if R.ContainsAny(norm, terms.position) then
        return A.RouterClassResourceProblemReply(
            "Class Resources position help",
            "Class Resource position is controlled by Class Resources anchor, X/Y offsets, width mode, and optional anchoring to Essential Cooldowns or the player power bar. I should not guess a new position from a problem report; name the direction when you want a move.",
            "move class resources down 5; anchor class resources to player; open class resources.",
            "Open Class Resources | Check Class Resources"
        )
    end

    if R.ContainsAny(norm, terms.color) then
        return A.RouterClassResourceProblemReply(
            "Class Resources color help",
            "Class Resource colors are separate from global frame colors. Combo points, holy power, runes, arcane charges, backgrounds, and separators can have their own color options depending on the resource.",
            "make combo points blue; make holy power background black; open class resources.",
            "Open Class Resources | Open Colors"
        )
    end

    return nil
end

A.RouterGameplayProblemTerms = A.RouterGameplayProblemTerms or {
    combatTimer = { "combat timer", "combat status", "combat enter", "combat leave" },
    crosshair = { "combat crosshair", "crosshair" },
    totem = { "totem", "totems", "totem frame", "totem icons", "statue", "statue frame" },
    position = {
        "wrong position", "position is wrong", "wrong place", "not moving",
        "does not move", "doesn't move", "cannot move", "can't move", "cant move",
        "anchor is wrong", "offset is wrong", "offset wrong", "stuck", "off screen",
    },
    color = {
        "wrong color", "color is wrong", "color wrong", "wrong colours", "colour is wrong",
        "too dark", "too bright", "hard to see", "too faded",
    },
    size = {
        "wrong size", "size is wrong", "too small", "too big", "too large", "too tiny",
    },
}

A.RouterGameplayProblemReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Gameplay helper help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "open gameplay; check combat timer.") .. "\nYou can ask: " .. tostring(actions or "Open Gameplay | Run Checks"),
        status = "info",
        summary = "Assistant gameplay help",
    }
end

function R.GameplaySettingFollowupResults(settingLabel)
    settingLabel = tostring(settingLabel or "")
    if settingLabel:find("Position", 1, true) then
        return R.PageFollowupResults("gameplay", "Gameplay", settingLabel .. " is controlled by related anchor, lock, click-through, and X/Y offset controls in Gameplay.")
    end
    return R.SettingFollowupResultsByQuery(settingLabel, settingLabel)
        or R.PageFollowupResults("gameplay", "Gameplay", settingLabel .. " lives in Gameplay.")
end

A.RouterTryGameplaySettingShortcut = function(norm, isCombatTimer, isCrosshair, isTotem)
    if not R.AsksSettingLocation(norm) then return nil end

    local label = isCombatTimer and "Combat Timer" or (isCrosshair and "Combat Crosshair" or "Totem Frame")
    local noun = isCombatTimer and "combat timer" or (isCrosshair and "combat crosshair" or "totem frame")
    local settingLabel = label
    if R.ContainsAny(norm, { "position", "move", "anchor", "offset", "wrong place" }) then
        settingLabel = label .. " Position"
    elseif R.ContainsAny(norm, { "size", "bigger", "larger", "smaller", "thicker", "thickness" }) then
        settingLabel = label .. " Size"
    elseif R.ContainsAny(norm, { "color", "colour" }) then
        settingLabel = label .. " Color"
    end

    local reply = A.RouterGameplayProblemReply(
        settingLabel .. " setting location",
        "Gameplay help: " .. settingLabel .. " lives in Gameplay. Open Gameplay and use the " .. label .. " visibility, lock, click-through, size, anchor, and X/Y offset controls where that helper exposes them.",
        "open gameplay; turn off " .. noun .. "; move " .. noun .. " down 8; set " .. noun .. " size to 40.",
        "Open Gameplay | turn off " .. noun
    )
    reply.status = "applied"
    reply.result = "applied"
    reply.searchResults = R.GameplaySettingFollowupResults(settingLabel)
    return reply
end

A.RouterTryGameplayProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^search%s+") or norm:match("^find%s+") or norm:match("^look%s+for%s+")
        or norm:match("^suche%s+") or norm:match("^finde%s+")
    then
        return nil
    end

    local terms = A.RouterGameplayProblemTerms
    local isCombatTimer = R.ContainsAny(norm, terms.combatTimer)
    local isCrosshair = R.ContainsAny(norm, terms.crosshair)
    local isTotem = R.ContainsAny(norm, terms.totem)
    if not isCombatTimer and not isCrosshair and not isTotem then return nil end

    local settingResult = A.RouterTryGameplaySettingShortcut and A.RouterTryGameplaySettingShortcut(norm, isCombatTimer, isCrosshair, isTotem)
    if settingResult then return settingResult end

    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm)
    if (wantsOff or wantsOn) and type(coreHandler) == "function" then
        local noun = isCombatTimer and "combat timer" or (isCrosshair and "combat crosshair" or "totem frame")
        local label = isCombatTimer and "Combat Timer" or (isCrosshair and "Combat Crosshair" or "Totem Frame")
        local verb = wantsOff and "turn off " or "turn on "
        return R.CoreControl(
            coreHandler,
            verb .. noun,
            label .. " lives in Gameplay. Ask: open gameplay, or " .. verb .. noun .. ".",
            "info"
        )
    end

    if type(coreHandler) == "function" then
        local noun = isCombatTimer and "combat timer" or (isCrosshair and "combat crosshair" or "totem frame")
        local amount = norm:match("[-+]?%d+")
        local direction
        if R.ContainsAny(norm, { "down" }) then direction = "down"
        elseif R.ContainsAny(norm, { "up" }) then direction = "up"
        elseif R.ContainsAny(norm, { "left" }) then direction = "left"
        elseif R.ContainsAny(norm, { "right" }) then direction = "right" end
        if amount and direction and R.ContainsAny(norm, { "move", "shift", "nudge" }) then
            return R.CoreControl(coreHandler, "move gameplay " .. noun .. " " .. direction .. " " .. amount, nil, "info")
        end
        if amount and R.ContainsAny(norm, { "size", "thickness" }) then
            return R.CoreControl(coreHandler, "set gameplay " .. noun .. " size to " .. amount, nil, "info")
        end
    end

    if norm:match("%d") and R.ContainsAny(norm, R.MUTATION_TERMS)
        and not R.ContainsAny(norm, terms.position)
        and not R.ContainsAny(norm, terms.color)
        and not R.ContainsAny(norm, terms.size)
        and not R.HasNaturalProblemTerm(norm)
    then
        return nil
    end

    if R.ContainsAny(norm, terms.position) then
        local label = isCombatTimer and "Combat Timer" or (isCrosshair and "Combat Crosshair" or "Totem Frame")
        return A.RouterGameplayProblemReply(
            label .. " position help",
            label .. " placement is controlled in Gameplay through lock, click-through, anchor, and X/Y offset options where that helper exposes them. Unlock or disable click-through when you need to drag or inspect it.",
            "open gameplay; move combat timer down 8; move totem icons right 6.",
            "Open Gameplay | Run Checks"
        )
    end

    if R.ContainsAny(norm, terms.color) then
        local label = isCrosshair and "Combat Crosshair" or (isCombatTimer and "Combat Timer" or "Totem Frame")
        return A.RouterGameplayProblemReply(
            label .. " color help",
            label .. " color options live in Gameplay when MSUF exposes them. For the crosshair, check in-range and out-of-range colors; for other helpers, check the exposed icon/text color options before changing global colors.",
            "set crosshair in range color green; set crosshair out of range color red; open gameplay.",
            "Open Gameplay | Open Colors"
        )
    end

    if R.ContainsAny(norm, terms.size) then
        local label = isCrosshair and "Combat Crosshair" or (isTotem and "Totem Frame" or "Combat Timer")
        return A.RouterGameplayProblemReply(
            label .. " size help",
            label .. " size is controlled in Gameplay through size, thickness, text size, or icon size options depending on the helper.",
            "set crosshair size to 60; set totem icon size to 40; open gameplay.",
            "Open Gameplay"
        )
    end

    return nil
end

function R.TryVisibilityDiagnosticShortcut(text, coreHandler)    if type(coreHandler) ~= "function" then return nil end
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if R.StartsWithVisibilityMutation and R.StartsWithVisibilityMutation(norm) then return nil end
    if not R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS)
        and not (R.ContainsAny(norm, { "sehe", "sehen" }) and R.ContainsAny(norm, { "nicht" }))
    then
        return nil
    end

    local group = R.VisibilityGroupForText(norm)
    local unit = R.VisibilityUnitForText(norm)
    local query

    if R.ContainsAny(norm, R.VISIBILITY_TARGET_SOUND_TERMS) then
        return {
            text = "Target sound help\nTarget sounds are Miscellaneous options. They only play when MSUF's target-sound option is enabled and WoW is allowed to play sounds. Check the target sound toggle first, then inspect WoW sound settings if MSUF is already enabled.\nExamples: turn on target sounds; open miscellaneous; check target sound.\nYou can ask: Open Miscellaneous",
            status = "info",
            summary = "Assistant target sound visibility help",
        }
    elseif R.ContainsAny(norm, R.VISIBILITY_ALTMANA_TERMS) then
        query = "check class resources"
    elseif R.ContainsAny(norm, R.VISIBILITY_CLASSPOWER_TERMS) then
        query = "check class resources"
    elseif R.ContainsAny(norm, R.VISIBILITY_AURA_TERMS) then
        local scope = R.VisibilityAuraScopeForText(group, unit)
        if scope then
            query = "why are " .. scope .. " " .. R.VisibilityAuraLaneForText(norm) .. " hidden"
        end
    elseif R.ContainsAny(norm, R.VISIBILITY_CASTBAR_TERMS) then
        local castbarUnit = R.VisibilityCastbarUnitForText(unit)
        if castbarUnit then
            query = "diagnose " .. castbarUnit .. " castbar"
        end
    else
        for i = 1, #R.VISIBILITY_GAMEPLAY_FEATURE_TERMS do
            local spec = R.VISIBILITY_GAMEPLAY_FEATURE_TERMS[i]
            if R.ContainsAny(norm, spec.terms) then
                query = spec.query
                break
            end
        end
    end

    if not query then
        if group then
            query = "why are " .. group .. " frames hidden"
        elseif unit then
            query = "diagnose " .. unit .. " frame"
        end
    end

    if not query then return nil end

    local result = coreHandler(query)
    if result and not (type(result) == "table" and result.kind == "unknown") then
        result.summary = result.summary or "Matched by a visibility diagnostic shortcut."
        return result
    end
    return nil
end

function A.RouterFriendlyNoMatch(text)
    local noMatch = R.KnowledgeNoMatch(text)
    if noMatch then return noMatch end
    local result = {
        text = "I'm not sure which MSUF request you mean yet. I can help once I can match the request to an MSUF menu option. Include the frame or page plus the option, for example 'set player width to 300', 'turn off raid range fade', or 'set target buff icon size to 30'. If that wording should work, send the full text in Discord: " .. R.DISCORD_INVITE,
        status = "info",
        summary = "Assistant request unclear",
    }
    if A.RecordNoMatch then A.RecordNoMatch(text, result, "router") end
    return result
end

function A.RouterIsNoClueResult(result)
    if type(result) ~= "table" then return true end
    local msg = tostring(result.text or "")
    local looksLikeNoOption = msg:find("  do not know that setting yet", 1, true) or msg:find("  could not match that setting yet", 1, true) or msg:find("  do not know that option yet", 1, true) or msg:find("  could not match that option yet", 1, true) or msg:find("does not match an MSUF aura option yet", 1, true)
    if result.kind == "unknown" and (msg == "" or looksLikeNoOption) then return true end
    if result.status == "failed" and looksLikeNoOption then return true end
    if result.status == "failed" and (msg:find("could not parse", 1, true) or msg:find("could not understand", 1, true)) then return true end
    return false
end

function A.RouterIsUnknownResult(result)
    if type(result) ~= "table" then return true end
    if result.kind == "unknown" then return true end
    local msg = tostring(result.text or "")
    if result.status == "failed" and msg:find("do not know", 1, true) then return true end
    if result.status == "failed" and (msg:find("could not parse", 1, true) or msg:find("could not understand", 1, true)) then return true end
    if result.status == "failed" and msg:find("not registered", 1, true) then return true end
    if result.status == "failed" and msg:find("unsupported", 1, true) then return true end
    return false
end

function A.RouterIsAmbiguousResult(result)
    return type(result) == "table" and (result.kind == "ambiguous" or result.status == "ambiguous")
end

local function ClearStaleContextPendingConfirmation()
    if A.pendingConfirmation ~= nil then return false end
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" and ctx.pendingConfirmation ~= nil then
        ctx.pendingConfirmation = nil
        return true
    end
    return false
end

function A.RouterSnapshotPendingState()
    ClearStaleContextPendingConfirmation()
    local ctx = A.GetContext and A.GetContext()
    return {
        pendingConfirmation = A.pendingConfirmation,
        pendingChoices = A.pendingChoices,
        pendingResults = A.pendingResults,
        pendingSelectedResult = A.pendingSelectedResult,
        pendingFlow = A.pendingFlow,
        ctx = ctx,
        ctxPendingConfirmation = ctx and ctx.pendingConfirmation,
        ctxPendingChoices = ctx and ctx.pendingChoices,
        ctxPendingResults = ctx and ctx.pendingResults,
        ctxPendingSelectedResult = ctx and ctx.pendingSelectedResult,
        ctxPendingFlow = ctx and ctx.pendingFlow,
    }
end

function A.RouterRestorePendingState(state)
    if type(state) ~= "table" then return end
    A.pendingConfirmation = state.pendingConfirmation
    A.pendingChoices = state.pendingChoices
    A.pendingResults = state.pendingResults
    A.pendingSelectedResult = state.pendingSelectedResult
    A.pendingFlow = state.pendingFlow
    local ctx = state.ctx
    if type(ctx) == "table" then
        ctx.pendingConfirmation = state.ctxPendingConfirmation
        ctx.pendingChoices = state.ctxPendingChoices
        ctx.pendingResults = state.ctxPendingResults
        ctx.pendingSelectedResult = state.ctxPendingSelectedResult
        ctx.pendingFlow = state.ctxPendingFlow
    end
end


function A.RouterHasPendingAssistantState()
    if A.pendingConfirmation ~= nil then return true end
    ClearStaleContextPendingConfirmation()
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return true end
    if type(A.pendingFlow) == "table" then return true end
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        if type(ctx.pendingChoices) == "table" and #ctx.pendingChoices > 0 then return true end
        if ctx.pendingFlow ~= nil then return true end
        if type(ctx.guidedSetup) == "table" then return true end
    end
    return false
end

function A.RouterHasPendingChoices()
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return true end
    local ctx = A.GetContext and A.GetContext()
    return type(ctx) == "table" and type(ctx.pendingChoices) == "table" and #ctx.pendingChoices > 0
end

function A.RouterClearPendingChoicesForRoute()
    A.pendingChoices = nil
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then ctx.pendingChoices = nil end
end

function A.RouterClearPendingResultsForRoute()
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
end

function A.RouterHasPendingConfirmationOrFlow()
    if A.pendingConfirmation ~= nil then return true end
    ClearStaleContextPendingConfirmation()
    if type(A.pendingFlow) == "table" then return true end
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        if ctx.pendingFlow ~= nil then return true end
    end
    return false
end

function A.RouterHasBlockingPendingAssistantState()
    if A.pendingConfirmation ~= nil then return true end
    ClearStaleContextPendingConfirmation()
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return true end
    if type(A.pendingFlow) == "table" then return true end
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        if type(ctx.pendingChoices) == "table" and #ctx.pendingChoices > 0 then return true end
        if ctx.pendingFlow ~= nil then return true end
    end
    return false
end

function A.RouterHasPendingSearchResults()
    if type(A.pendingResults) == "table" and #A.pendingResults > 0 then return true end
    local ctx = A.GetContext and A.GetContext()
    return type(ctx) == "table" and type(ctx.pendingResults) == "table" and #ctx.pendingResults > 0
end

function A.RouterHasPendingSelectedResult()
    if type(A.HasPendingSelectedResult) == "function" and A.HasPendingSelectedResult() then return true end
    if type(A.pendingSelectedResult) == "table" then return true end
    local ctx = A.GetContext and A.GetContext()
    return type(ctx) == "table" and type(ctx.pendingSelectedResult) == "table"
end

R.RESULT_ORDINAL_WORDS = {    "first", "second", "third", "fourth", "fifth",
    "sixth", "seventh", "eighth", "ninth", "tenth",
}

R.RESULT_NUMBER_WORDS = R.RESULT_NUMBER_WORDS or {
    "one", "two", "three", "four", "five",
    "six", "seven", "eight", "nine", "ten",
}

R.RESULT_LIST_POSITION_TERMS = R.RESULT_LIST_POSITION_TERMS or {
    first = { "top", "top one", "top result", "top option", "top choice", "top item", "first listed", "first listed result", "first listed option" },
    penultimate = { "second last", "second to last", "second from bottom", "next to last", "penultimate", "2nd last", "2nd to last", "2nd from bottom" },
    last = { "last", "last one", "last result", "last option", "last choice", "last item", "bottom", "bottom one", "bottom result", "bottom option", "final", "final one", "final result", "final option" },
}

R.RESULT_ADJACENT_TERMS = R.RESULT_ADJACENT_TERMS or {
    next = {
        "next one", "next result", "next option", "next choice", "next item",
        "following one", "following result", "following option",
        "one after", "result after", "option after", "one below", "below result",
        "next",
    },
    previous = {
        "previous one", "previous result", "previous option", "previous choice", "previous item",
        "prev one", "prev result", "prior one", "prior result",
        "one before", "result before", "option before", "one above", "above result",
        "previous", "prev", "prior",
    },
}

function R.OrdinalSuffixForIndex(index)    index = tonumber(index)
    if not index then return nil end
    local suffix = "th"
    if index % 100 < 11 or index % 100 > 13 then
        local last = index % 10
        if last == 1 then suffix = "st"
        elseif last == 2 then suffix = "nd"
        elseif last == 3 then suffix = "rd" end
    end
    return tostring(index) .. suffix
end

R.RESULT_ORDINAL_NOUNS = { "one", "result", "option", "choice", "item", "match" }
R.RESULT_ORDINAL_ACTIONS = {    "open", "show", "show me", "explain", "describe", "tell me about",
    "what is", "what does", "is", "run", "execute", "use", "apply", "select", "pick",
    "compare", "set", "change", "make", "turn", "enable", "disable", "hide",
    "increase", "decrease", "raise", "lower", "where is", "where do i change",
    "where can i change", "which page is", "what page is", "what menu is",
    "current value of", "value of", "why", "what about", "how about", "what can i set",
    "move", "nudge", "shift", "put", "place", "position", "anchor",
    "bring", "send", "push", "pull",
}

function R.ResultOrdinalActionTargetMatches(norm, target)    target = R.Normalize(target)
    if norm == target then return true end
    if norm:sub(1, #target + 1) ~= target .. " " then return false end
    local tail = R.Trim(norm:sub(#target + 2))
    if tail == "" then return true end
    if tail == "on" or tail == "off" or tail == "enabled" or tail == "disabled" then return true end
    if tail == "up" or tail == "down" or tail == "higher" or tail == "lower" then return true end
    if tail == "bigger" or tail == "larger" or tail == "smaller" or tail == "shorter" or tail == "taller" then return true end
    if tail == "left" or tail == "right" or tail == "forward" or tail == "back" or tail == "backward" then return true end
    if tail == "for" or tail == "used for" or tail == "help with" or tail == "do" then return true end
    if tail == "to" or tail == "at" then return true end
    if tail:sub(1, 3) == "to " then return true end
    if tail:match("^left%s+") or tail:match("^right%s+") or tail:match("^up%s+") or tail:match("^down%s+") then return true end
    if tail:match("^bigger%s+") or tail:match("^larger%s+") or tail:match("^smaller%s+") then return true end
    if tail:sub(1, 4) == "and " then return true end
    return false
end

function R.LooksLikeResultOrdinalReply(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if R.ContainsAny(norm, {
        "first two", "first 2", "the first two", "the first 2",
        "top two", "top 2", "the top two", "the top 2",
    }) and R.ContainsAny(norm, { "compare", "difference", "differences", "result", "results", "option", "options", "choice", "choices" }) then
        return true
    end
    local ordinalCompare = R.ContainsAny(norm, { "vs", "versus" })
    for i = 1, #R.RESULT_ORDINAL_WORDS do
        local word = R.RESULT_ORDINAL_WORDS[i]
        if norm == word or norm == "the " .. word then return true end
        if ordinalCompare and R.HasNormalizedPhrase(norm, word) then return true end
        for j = 1, #R.RESULT_ORDINAL_NOUNS do
            local noun = R.RESULT_ORDINAL_NOUNS[j]
            if R.HasNormalizedPhrase(norm, word .. " " .. noun)
                or R.HasNormalizedPhrase(norm, "the " .. word .. " " .. noun) then
                return true
            end
            if noun ~= "one"
                and (R.HasNormalizedPhrase(norm, noun .. " " .. word)
                    or R.HasNormalizedPhrase(norm, "the " .. noun .. " " .. word)) then
                return true
            end
        end
        for j = 1, #R.RESULT_ORDINAL_ACTIONS do
            local action = R.RESULT_ORDINAL_ACTIONS[j]
            if R.ResultOrdinalActionTargetMatches(norm, action .. " the " .. word)
                or R.ResultOrdinalActionTargetMatches(norm, action .. " " .. word) then
                return true
            end
        end
    end
    return false
end

function R.LooksLikeResultNumericReply(text)    if not A.RouterHasPendingSearchResults() then return false end
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if norm:match("^%d+%a*$") or norm:match("^the%s+%d+%a*$") then return true end
    for j = 1, #R.RESULT_ORDINAL_ACTIONS do
        local action = R.Normalize(R.RESULT_ORDINAL_ACTIONS[j])
        if action ~= "" and norm:sub(1, #action + 1) == action .. " " then
            local tail = R.Trim(norm:sub(#action + 2))
            if tail:match("^the%s+%d+%a*") or tail:match("^%d+%a*") then return true end
        end
    end
    if R.ContainsAny(norm, { "compare", "difference", "differences", "vs", "versus" }) and norm:match("%d+") then return true end
    for i = 1, 10 do
        local tokens = { tostring(i) }
        local ordinalToken = R.OrdinalSuffixForIndex(i)
        if ordinalToken then tokens[#tokens + 1] = ordinalToken end
        for tokenIndex = 1, #tokens do
            local token = tokens[tokenIndex]
            for j = 1, #R.RESULT_ORDINAL_ACTIONS do
                local action = R.RESULT_ORDINAL_ACTIONS[j]
                if R.ResultOrdinalActionTargetMatches(norm, action .. " the " .. token)
                    or R.ResultOrdinalActionTargetMatches(norm, action .. " " .. token) then
                    return true
                end
            end
        end
    end
    return false
end

function R.LooksLikeResultListPositionReply(text)    if not A.RouterHasPendingSearchResults() then return false end
    local norm = R.Normalize(text)
    if norm == "" then return false end
    local function termMatches(term)
        term = R.Normalize(term)
        if term == "" then return false end
        if norm == term or norm == "the " .. term then return true end
        if R.HasNormalizedPhrase(norm, term) then return true end
        for j = 1, #R.RESULT_ORDINAL_ACTIONS do
            local action = R.RESULT_ORDINAL_ACTIONS[j]
            if R.ResultOrdinalActionTargetMatches(norm, action .. " the " .. term)
                or R.ResultOrdinalActionTargetMatches(norm, action .. " " .. term) then
                return true
            end
        end
        if R.ContainsAny(norm, { "vs", "versus", "compare", "difference", "better" }) and R.HasNormalizedPhrase(norm, term) then
            return true
        end
        return false
    end
    for _, terms in pairs(R.RESULT_LIST_POSITION_TERMS or {}) do
        for i = 1, #terms do
            if termMatches(terms[i]) then return true end
        end
    end
    return false
end

function R.LooksLikeResultAdjacentReply(text)    if not (A.RouterHasPendingSearchResults() and A.RouterHasPendingSelectedResult()) then return false end
    local norm = R.Normalize(text)
    if norm == "" then return false end
    local penultimateMention = false
    for _, term in ipairs((R.RESULT_LIST_POSITION_TERMS and R.RESULT_LIST_POSITION_TERMS.penultimate) or {}) do
        if R.HasNormalizedPhrase(norm, term) then
            penultimateMention = true
            break
        end
    end
    local compareIntent = R.ContainsAny(norm, { "compare", "difference", "differences", "vs", "versus", "better" })
    local function compareMentions(term)
        if not compareIntent then return false end
        local padded = " " .. norm .. " "
        if padded:find(" compare " .. term .. " ", 1, true)
            or padded:find(" between " .. term .. " ", 1, true) then
            return true
        end
        for _, separator in ipairs({ " vs ", " versus ", " and ", " or ", " to ", " with " }) do
            if padded:find(" " .. term .. separator, 1, true)
                or padded:find(separator .. term .. " ", 1, true) then
                return true
            end
        end
        return false
    end
    local function termMatches(term)
        term = R.Normalize(term)
        if term == "" then return false end
        if penultimateMention and term == "next" then return false end
        if norm == term or norm == "the " .. term then return true end
        local bare = term:find("%s", 1, true) == nil
        if not bare and R.HasNormalizedPhrase(norm, term) then return true end
        for j = 1, #R.RESULT_ORDINAL_ACTIONS do
            local action = R.RESULT_ORDINAL_ACTIONS[j]
            if R.ResultOrdinalActionTargetMatches(norm, action .. " the " .. term)
                or R.ResultOrdinalActionTargetMatches(norm, action .. " " .. term) then
                return true
            end
        end
        return compareMentions(term)
    end
    for _, terms in pairs(R.RESULT_ADJACENT_TERMS or {}) do
        for i = 1, #terms do
            if termMatches(terms[i]) then return true end
        end
    end
    return false
end

function R.LooksLikeResultOrdinalSuffixReply(text)    if not A.RouterHasPendingSearchResults() then return false end
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if norm:match("^%d+%a%a$") or norm:match("^the%s+%d+%a%a$") then return true end
    for i = 1, 10 do
        local token = R.OrdinalSuffixForIndex(i)
        if token then
            for j = 1, #R.RESULT_ORDINAL_NOUNS do
                local noun = R.RESULT_ORDINAL_NOUNS[j]
                if noun ~= "one"
                    and (R.HasNormalizedPhrase(norm, noun .. " " .. token)
                        or R.HasNormalizedPhrase(norm, "the " .. noun .. " " .. token)
                        or R.HasNormalizedPhrase(norm, token .. " " .. noun)
                        or R.HasNormalizedPhrase(norm, "the " .. token .. " " .. noun)) then
                    return true
                end
            end
            for j = 1, #R.RESULT_ORDINAL_ACTIONS do
                local action = R.RESULT_ORDINAL_ACTIONS[j]
                if R.ResultOrdinalActionTargetMatches(norm, action .. " the " .. token)
                    or R.ResultOrdinalActionTargetMatches(norm, action .. " " .. token) then
                    return true
                end
            end
            if R.ContainsAny(norm, { "vs", "versus" }) and R.HasNormalizedPhrase(norm, token) then return true end
        end
    end
    return false
end

function R.LooksLikeResultNumberWordReply(text)    if not A.RouterHasPendingSearchResults() then return false end
    local norm = R.Normalize(text)
    if norm == "" then return false end
    for i = 1, #R.RESULT_NUMBER_WORDS do
        local word = R.RESULT_NUMBER_WORDS[i]
        if norm == word or norm == "the " .. word then return true end
        if R.HasNormalizedPhrase(norm, "result " .. word)
            or R.HasNormalizedPhrase(norm, "option " .. word)
            or R.HasNormalizedPhrase(norm, "choice " .. word)
            or R.HasNormalizedPhrase(norm, "number " .. word) then
            return true
        end
        for j = 1, #R.RESULT_ORDINAL_ACTIONS do
            local action = R.RESULT_ORDINAL_ACTIONS[j]
            if R.ResultOrdinalActionTargetMatches(norm, action .. " the " .. word)
                or R.ResultOrdinalActionTargetMatches(norm, action .. " " .. word) then
                return true
            end
        end
    end
    return false
end

function R.LooksLikePendingResultReply(text)    local norm = R.Normalize(text)
    if norm == "" then return false end
    if (R.HasNormalizedPhrase(norm, "current value") or R.HasNormalizedPhrase(norm, "value now"))
        and R.LastChangeFollowupHasExplicitOtherSubject and R.LastChangeFollowupHasExplicitOtherSubject(norm)
    then
        if not (norm:match("result%s+%d+")
            or norm:match("option%s+%d+")
            or norm:match("choice%s+%d+")
            or norm:match("#%d+")
            or R.LooksLikeResultOrdinalReply(text)
            or R.LooksLikeResultOrdinalSuffixReply(text)
            or R.LooksLikeResultNumericReply(text)
            or R.LooksLikeResultListPositionReply(text)
            or R.LooksLikeResultAdjacentReply(text)
            or (A._PendingResultLabelReply and A._PendingResultLabelReply(text))
            or R.LooksLikeResultNumberWordReply(text)) then
            return false
        end
    end
    if R.LooksLikeRegistrySettingDecisionQuestion and R.LooksLikeRegistrySettingDecisionQuestion(norm) then return false end
    if R.LooksLikeRegistrySettingTroubleshootingQuestion and R.LooksLikeRegistrySettingTroubleshootingQuestion(norm) then return false end
    if norm:match("^%d+$") then return true end
    if norm:match("#%d+") then return true end
    if A._PendingResultLabelReply and A._PendingResultLabelReply(text) then return true end
    if R.LooksLikeResultNumericReply(text) then return true end
    if R.LooksLikeResultListPositionReply(text) then return true end
    if R.LooksLikeResultAdjacentReply(text) then return true end
    if R.LooksLikeResultOrdinalSuffixReply(text) then return true end
    if R.LooksLikeResultNumberWordReply(text) then return true end
    if norm:match("^run%s+%d+") or norm:match("^execute%s+%d+") or norm:match("^compare%s+%d+") then return true end
    if R.IsStandaloneCancelReply(text) then return true end
    if R.LooksLikeResultOrdinalReply(text) then return true end
    if norm == "explain" or norm == "details" or norm == "describe"
        or norm == "open" or norm == "show me"
        or norm == "current value" or norm == "value now"
        or norm == "why" or norm == "related" then
        return true
    end
    if R.ContainsAny(norm, {
        "open it", "open that", "open this",
        "where is it", "where is that", "where is this",
        "where are they", "where are these", "where are those",
        "where do i change it", "where do i change that", "where do i change this",
        "where can i change it", "where can i change that", "where can i change this",
        "which page is it on", "which page is that on", "which page is this on",
        "what page is it on", "what page is that on", "what page is this on",
        "what menu is it in", "what menu is that in", "what menu is this in",
        "show me where", "take me there", "go there",
        "tell me more", "more details",
        "more options", "more settings", "more like this",
        "other options", "other settings", "related options", "related settings",
        "similar options", "similar settings", "what else",
        "why would i use it", "why would i use this", "why would i use that",
        "why should i use it", "why should i use this", "why should i use that",
        "what is it for", "what is this for", "what is that for",
        "what does it help with", "what does this help with", "what does that help with",
        "which one should i", "which should i",
        "which result should i", "which option should i",
        "what should i pick", "what should i use", "what should i choose",
        "should i use", "should i pick", "should i choose", "should i change", "should i open",
        "what should i change first", "which should i change first",
        "which one is safer", "which result is safer", "which option is safer",
        "safest result", "safest option", "best result", "best option",
        "recommend a result", "recommend an option", "recommend one",
    }) then
        return true
    end
    if R.ContainsAny(norm, {
        "compare them", "compare these", "compare those",
        "compare the results", "compare results", "compare listed results",
        "compare the options", "compare options", "compare listed options",
        "difference between them", "differences between them",
        "difference between the results", "differences between the results",
        "which is better", "which one is better",
    }) then
        return true
    end
    if A.RouterHasPendingSearchResults() and R.ContainsAny(norm, {
        "what can i set", "what can it be", "what can this be", "what can that be",
        "what values", "which values", "allowed values", "supported values",
        "valid values", "available values", "possible values",
        "what choices", "which choices", "available choices", "supported choices",
        "choices for", "options for this", "options for it",
        "what range", "which range", "allowed range", "supported range", "valid range",
        "minimum", "maximum", "min max",
    }) then
        return true
    end
    if A.RouterHasPendingSelectedResult() and R.ContainsAny(norm, {
        "simpler", "more simple", "simple explanation", "in simple words", "plain english", "plain language",
        "i dont understand", "i do not understand", "what does that mean", "what does it mean",
    }) then
        return true
    end
    if A.RouterHasPendingSelectedResult() and R.ContainsAny(norm, {
        "current value", "value now", "what is it set to", "what is this set to", "what is that set to",
        "what is the result set to", "what is the option set to", "what is it now", "what is this now",
        "what is that now", "what is the value", "what value is it", "is it on", "is it off",
        "is it enabled", "is it disabled",
    }) then
        return true
    end
    if A.RouterHasPendingSelectedResult() and R.ContainsAny(norm, {
        "why this", "why that", "why it", "why this option", "why that option",
        "why this result", "why that result", "why would i use it", "why should i use it",
        "what is it for", "what is this for", "what is that for",
        "what does it help with", "what does this help with", "what does that help with",
        "purpose", "reason",
    }) then
        return true
    end
    if R.ContainsAny(norm, { "it", "that", "this", "the result", "the option", "that result", "that option", "this result", "this option" })
        and (R.ContainsAny(norm, R.MUTATION_TERMS) or R.ContainsAny(norm, {
            "explain it", "explain that", "explain this",
            "what does it", "what does that", "what does this",
            "tell me about it", "tell me about that",
            "open it", "open that", "show it", "show that", "show me where",
            "run it", "run that", "execute it", "execute that",
            "compare it", "compare that", "compare this",
            "difference between it", "difference between that", "difference between this",
        }))
    then
        return true
    end
    return R.ContainsAny(norm, {
        "result", "option 1", "option 2", "option 3", "option 4", "option 5",
        "choice 1", "choice 2", "choice 3", "choice 4", "choice 5",
        "open option", "open choice", "explain option", "explain choice",
        "what does option", "what does result", "run option", "run choice",
        "execute option", "execute choice", "compare result", "compare option", "compare choice",
    })
end

R.CORRECTION_HISTORY_TERMS = {    "what did you change", "what changed", "what was changed", "what did you do",
    "what did you just do", "what did you just change", "what exactly did you change",
    "what exactly did you just do", "what did you set", "last change", "last assistant change",
    "previous change", "what is it now", "what is it set to", "current value", "value now",
    "show last change", "show me last change", "show me the last change",
    "was hast du geaendert", "was hast du gerade geaendert", "was hast du gemacht",
    "was hast du gerade gemacht", "was wurde geaendert", "was ist geaendert",
    "letzte aenderung", "zeige letzte aenderung", "zeig letzte aenderung",
}

R.CORRECTION_UNDO_TERMS = {    "undo", "undo that", "undo this", "undo last", "undo last change", "undo please",
    "revert", "revert that", "revert this", "revert last", "revert last change",
    "rollback", "roll back", "roll back that", "roll back last change",
    "take it back", "take that back", "back out that change",
    "restore previous", "restore previous value", "restore previous change",
    "restore last value", "restore last change", "put it back", "put that back",
    "make it like before", "that was wrong", "this was wrong", "wrong change",
    "i changed the wrong thing", "i changed wrong thing", "i did the wrong change",
    "i do not like that", "i dont like that", "i do not like this", "i dont like this",
    "do not like that", "dont like that", "not like that", "bad change",
    "cancel that change", "cancel this change", "cancel last change",
    "nevermind undo", "never mind undo", "nevermind revert", "never mind revert",
    "nevermind that", "never mind that", "actually undo", "actually revert",
    "rueckgaengig", "rueckgaengig machen", "mach das rueckgaengig",
    "mach es rueckgaengig", "das rueckgaengig machen", "zuruecknehmen",
    "nimm das zurueck", "mach das zurueck", "wieder zurueck",
    "das war falsch", "das ist falsch", "falsche aenderung",
}

R.CORRECTION_REDO_TERMS = {    "redo", "redo that", "redo this", "redo last", "redo last change",
    "reapply", "reapply that", "apply it again", "do it again",
    "restore undone change", "restore the undone change", "repeat that",
    "repeat last change", "wiederholen", "erneut anwenden",
}

function R.ControlResult(text, status)    return {
        text = text,
        status = status or "info",
        result = status or "info",
        summary = "Assistant correction flow",
    }
end

function R.CoreControl(coreHandler, command, fallbackText, fallbackStatus)    if type(coreHandler) == "function" then
        local result = coreHandler(command)
        if result and not A.RouterIsUnknownResult(result) then return result end
    end
    return R.ControlResult(fallbackText, fallbackStatus)
end

function R.TryCorrectionShortcut(text, coreHandler)    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if norm:match("^can%s+i%s+undo") or norm:match("^can%s+you%s+undo")
        or norm:match("^can%s+i%s+redo") or norm:match("^can%s+you%s+redo")
    then
        return nil
    end
    if (R.HasNormalizedPhrase(norm, "current value") or R.HasNormalizedPhrase(norm, "value now"))
        and R.LastChangeFollowupHasExplicitOtherSubject and R.LastChangeFollowupHasExplicitOtherSubject(norm)
    then
        return nil
    end

    if R.ContainsAny(norm, R.CORRECTION_REDO_TERMS) then
        return R.CoreControl(coreHandler, "redo", "I have no Assistant change to redo.", "failed")
    end

    if R.ContainsAny(norm, R.CORRECTION_UNDO_TERMS) then
        return R.CoreControl(coreHandler, "undo", "I have no Assistant change to undo.", "failed")
    end

    if R.ContainsAny(norm, R.CORRECTION_HISTORY_TERMS) then
        return R.CoreControl(coreHandler, "what did you change", "I do not have a recorded Assistant change yet.", "info")
    end

    return nil
end

A.RouterAssistantUsabilityProblemTerms = A.RouterAssistantUsabilityProblemTerms or {
    assistant = {
        "assistant", "assistent", "chat", "chat box", "input box", "answer", "response",
        "panel", "history",
    },
    matching = {
        "not answering", "does not answer", "doesn't answer", "not responding",
        "does not understand", "doesn't understand", "cannot understand", "can't understand",
        "cant understand", "keeps giving search results", "keeps searching", "wrong results",
        "search results are wrong", "answered in german", "answer is german",
        "output is too long", "too much text", "too verbose",
    },
    search = {
        "menu search", "search results", "search result", "where is search",
        "search not working", "search does not work", "search doesn't work",
        "search is wrong", "search results are wrong",
    },
    size = {
        "assistant panel is too small", "assistant panel too small", "chat box is too small",
        "chat box too small", "input box is too small", "menu is too small",
        "menu too small", "options window is too big", "menu is off screen",
        "menu off screen", "menu offscreen", "recover menu offscreen",
    },
    undo = {
        "how do i undo", "how can i undo", "undo not working", "undo does not work",
        "undo doesn't work", "redo not working", "redo does not work", "redo doesn't work",
        "assistant history is missing", "history is missing", "history missing",
    },
    support = {
        "support link not working", "support links not working", "discord link not working",
        "discord not working", "support link broken", "discord link broken",
    },
    recovery = {
        "factory reset scares me", "factory reset is scary", "factory reset risky",
        "i reset everything by accident", "reset everything by accident",
        "reset all by accident", "i reset all by accident",
    },
    checks = {
        "run checks not working", "checks not working", "checks do not work",
        "diagnostics not working", "diagnostic not working",
    },
}

A.RouterAssistantUsabilityReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Assistant help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "run checks; open display recovery; ask where a setting is.") .. "\nYou can ask: " .. tostring(actions or "Run Checks | Open Display & Recovery | Assistant Support Text"),
        status = "info",
        summary = "Assistant usability help",
    }
end

A.RouterTryAssistantUsabilityProblemShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    local terms = A.RouterAssistantUsabilityProblemTerms

    if R.ContainsAny(norm, {
        "factory reset", "full reset", "reset everything", "reset all settings",
        "reset all profiles", "factory defaults",
    })
        and (R.AsksSettingLocation(norm)
            or norm:match("^can%s+i%s+") ~= nil
            or norm:match("^should%s+i%s+") ~= nil
            or R.ContainsAny(norm, { "what is", "what does", "is it safe", "explain" }))
    then
        return A.RouterAssistantUsabilityReply(
            "Factory reset help",
            "Factory Reset lives in Display & Recovery and is confirmation-gated because it can change many saved options. Export or copy the active profile before using it if you may need to recover the current setup.",
            "open display recovery; export current profile; factory reset all.",
            "Open Display & Recovery | Export Current Profile | Check Profiles"
        )
    end

    if R.ContainsAny(norm, terms.undo) then
        return A.RouterAssistantUsabilityReply(
            "Undo and history help",
            "Use undo to revert the last Assistant-made setting change, redo to reapply it, and 'what did you change' to inspect the last recorded Assistant change. If there is no recorded Assistant change, undo has nothing safe to revert.",
            "undo; redo; what did you change; show last change.",
            "Undo | Redo | What Did You Change"
        )
    end

    if R.ContainsAny(norm, terms.recovery) then
        return A.RouterAssistantUsabilityReply(
            "Factory reset and recovery help",
            "Factory reset is intentionally confirmation-gated because it can change many saved options. If something was reset by accident, first avoid making more broad changes, check Profiles, use undo if the Assistant made the last change, and open Display & Recovery for support text.",
            "cancel; undo; check profiles; open display recovery.",
            "Open Display & Recovery | Check Profiles | Assistant Support Text"
        )
    end

    if R.ContainsAny(norm, terms.support) then
        return A.RouterAssistantUsabilityReply(
            "Support link help",
            "Support links are local Dashboard actions. If a link does not open from the WoW client, copy the support link text and paste it in a browser instead. Include the exact Assistant prompt and the result when reporting an issue.",
            "copy support link; show support links; assistant support text.",
            "Show Support Links | Copy Support Link | Assistant Support Text"
        )
    end

    if R.ContainsAny(norm, terms.checks) then
        return A.RouterAssistantUsabilityReply(
            "Checks and diagnostics help",
            "Run Checks inspects common MSUF state locally. If a check result looks wrong, name the broken area so I can run a more specific diagnostic, or generate support text for a report.",
            "run checks; why is target cast bar hidden; why are party frames hidden; assistant support text.",
            "Run Checks | Assistant Support Text | Open Display & Recovery"
        )
    end

    if R.ContainsAny(norm, terms.search) then
        return A.RouterAssistantUsabilityReply(
            "Menu search help",
            "MSUF search uses the local menu index. For better results, include the frame or page plus the option area, such as target buffs, raid ready check, or cast bar interrupt color. If results look wrong, ask me to explain a result or search with more scope words.",
            "search target buff cooldown text; help me find raid ready checks; explain result 1.",
            "Open Dashboard | What Can I Change Here | Assistant Support Text"
        )
    end

    if R.ContainsAny(norm, terms.size) then
        return A.RouterAssistantUsabilityReply(
            "Menu and Assistant size help",
            "Dashboard scaling controls the MSUF menu scale, MSUF frame scale, and WoW UI scale. If the menu is outside the visible area, open Display & Recovery or Dashboard Scaling before changing individual frame sizes.",
            "open dashboard scaling; open display recovery; set MSUF menu scale to 100.",
            "Open Dashboard Scaling | Open Display & Recovery"
        )
    end

    if R.ContainsAny(norm, terms.assistant) and R.ContainsAny(norm, terms.matching) then
        if R.ContainsAny(norm, { "german", "deutsch" }) then
            return A.RouterAssistantUsabilityReply(
                "Assistant language help",
                "The Assistant should answer in English for this build. Menu Language controls MSUF menu labels, while Assistant response wording is handled by the Assistant itself. If an answer appears in German, capture the exact prompt so it can be fixed.",
                "set menu language to English; assistant support text; report assistant bug.",
                "Open Miscellaneous | Assistant Support Text | Report Bug"
            )
        end
        return A.RouterAssistantUsabilityReply(
            "Assistant matching help",
            "I match best when you include the MSUF area and the thing you want changed or explained. Use concrete scope words like Player, Target, Raid, Auras, Cast Bars, Profiles, or Class Resources. If I return search results, ask me to explain a result or restate the request with the frame and option.",
            "why is target cast bar hidden; set target buff icon size to 30; where is profile export; explain result 1.",
            "What Can I Change Here | Run Checks | Assistant Support Text"
        )
    end

    return nil
end

A.RouterDecisionGuidanceTerms = A.RouterDecisionGuidanceTerms or {
    choose = {
        "which one is safer", "which option is safer", "which result is safer",
        "which one should i use", "which option should i use", "which result should i use",
        "which one should i pick", "which option should i choose", "which one should i choose",
        "choose the best one", "make the best choice", "choose for me", "pick for me",
        "do what you recommend", "apply recommended", "apply the recommended",
        "do the safe thing",
        "i dont know what to choose", "i don't know what to choose",
        "i do not know what to choose",
    },
    safety = {
        "is this safe", "is that safe", "is it safe", "will this break my profile",
        "will that break my profile", "will this break msuf", "will that break msuf",
        "will this mess up my ui", "will that mess up my ui", "can this break",
        "which settings are risky", "what settings are risky", "what is risky",
        "what changes are reversible", "which changes are reversible",
        "can you undo later", "can you undo this later", "can you undo that later",
        "can i undo later", "can i undo this later", "can i undo that later",
        "is this reversible",
    },
    explain = {
        "explain like im new", "explain like i'm new", "explain like i am new",
        "explain this simpler", "explain it simpler", "explain that simpler",
        "simple explanation please", "plain english", "plain language",
        "why would i change this", "why should i change this",
        "why would i use this", "why should i use this",
    },
}

A.RouterDecisionGuidanceReply = function(title, body, examples, actions)
    return {
        text = tostring(title or "Selection guidance") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "explain result 1; compare result 1 and result 2.") .. "\nYou can ask: " .. tostring(actions or "Explain Result 1 | Compare Results | Open Result 1"),
        status = "info",
        summary = "Assistant decision guidance",
    }
end

A.RouterTryDecisionGuidanceShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    local registrySettingDecisionResult = A.RouterTryRegistrySettingDecisionShortcut and A.RouterTryRegistrySettingDecisionShortcut(text, coreHandler)
    if registrySettingDecisionResult then return registrySettingDecisionResult end
    local terms = A.RouterDecisionGuidanceTerms
    local hasResults = A.RouterHasPendingSearchResults()
    local hasSelected = A.RouterHasPendingSelectedResult()

    if R.ContainsAny(norm, terms.safety) then
        if hasResults or hasSelected then
            return A.RouterDecisionGuidanceReply(
                "Safety guidance",
                "I can help assess a listed result, but I will not treat a vague safety question as permission to apply it. Inspect the result first, check its current value, or open the page before changing anything. Broad profile, import, delete, copy, reset, and factory-reset actions stay confirmation-gated.",
                "explain result 1; current value; open result 1; compare result 1 and result 2.",
                "Explain Result 1 | Current Value | Open Result 1 | Compare Results"
            )
        end
        return A.RouterDecisionGuidanceReply(
            "Safety guidance",
            "I need the exact MSUF option, action, or result before I can judge risk. Normal Assistant setting changes can be undone; broad profile and reset actions require confirmation before they run.",
            "search target buff cooldown text; explain result 1; undo; open display recovery.",
            "Search | Run Checks | Assistant Support Text"
        )
    end

    if R.ContainsAny(norm, terms.choose) then
        if hasResults or hasSelected then
            return A.RouterDecisionGuidanceReply(
                "Selection guidance",
                "I should not silently choose a result from a vague prompt. For a safe next step, ask me to explain or compare the listed results, then name the exact result or setting you want. Opening a result page is safer than applying a change.",
                "explain result 1; compare result 1 and result 2; open result 1; set result 1 to enabled.",
                "Explain Result 1 | Compare Results | Open Result 1"
            )
        end
        return A.RouterDecisionGuidanceReply(
            "Selection guidance",
            "I need an MSUF area or a listed result before I can help choose. Tell me the frame, page, or goal first, or start with Guided Setup if you want a safe step-by-step path.",
            "guided setup; make my UI better for healer; search target buffs; run checks.",
            "Guided Setup | Run Checks | What Can I Change Here"
        )
    end

    if R.ContainsAny(norm, terms.explain) then
        if hasResults or hasSelected then
            return A.RouterDecisionGuidanceReply(
                "Simple explanation help",
                "Tell me which listed result you want explained. I can summarize what it controls, where it lives, its current value when available, and a safe example command.",
                "explain result 1; explain result 2 in simple words; current value.",
                "Explain Result 1 | Current Value | Compare Results"
            )
        end
        return A.RouterDecisionGuidanceReply(
            "Simple explanation help",
            "Name the MSUF setting, page, or result you want explained. Without that context, I would only be guessing.",
            "what is range fade; explain target buff cooldown text; open cast bars.",
            "Open Player | Open Auras | Open Cast Bars"
        )
    end

    return nil
end

A.RouterSafePlanningTerms = A.RouterSafePlanningTerms or {
    automatic = {
        "fix my ui automatically", "fix everything automatically", "auto fix my ui",
        "automatically fix my ui", "make everything better", "make it better",
        "optimize my ui", "optimize my interface", "apply safe default",
        "apply safe defaults", "use safe default", "use safe defaults",
        "set safe default", "set safe defaults", "start from scratch",
    },
    checklist = {
        "give me a checklist", "show me a checklist", "setup checklist",
        "what should i check first", "what should i look at first",
        "what would you do next", "what would you change next",
        "what did you understand", "show me your plan",
    },
    diagnostic = {
        "can you diagnose my ui", "diagnose my ui", "diagnose msuf",
        "check my ui", "check my msuf setup", "check my setup",
    },
    backup = {
        "backup before changes", "backup my profile", "profile backup before",
        "make a backup", "make backup", "create a backup", "export before changes",
        "export profile before changes", "backup before guided setup",
    },
    compare = {
        "party frames vs raid frames", "party frame vs raid frame",
        "raid frames or mythic raid frames", "raid or mythic raid frames",
        "should i use party or raid frames", "should i use party frames or raid frames",
        "party or raid frames", "auras and filters", "auras vs filters",
        "aura filters vs aura layout", "castbar and unit frame", "castbar vs unit frame",
        "range fade vs alpha", "range fade and opacity", "range fade or opacity",
        "class resources vs power bar", "class resources and power bar",
        "power bar vs mana bar", "cast bar vs focus kick tracker", "castbar vs focus kick tracker",
        "target of target vs focus target", "boss frames vs target frame",
        "raid markers vs role icons", "raid marker vs role icon",
        "ready check vs role icon", "absorb bar vs heal prediction", "absorbs vs heal prediction",
        "incoming heals vs absorbs", "incoming heals and absorbs",
        "font outline vs font shadow", "cooldown swipe vs cooldown text",
        "stack text vs cooldown text", "growth direction vs anchor",
        "x offset vs anchor point", "menu scale vs ui scale",
        "msuf frame scale vs wow ui scale", "profile copy vs profile export",
        "profile import vs profile switch", "reset profile vs factory reset",
        "edit mode vs unlock frames", "blizzard frames vs msuf frames",
        "unit frames vs group frames", "group auras vs normal auras",
        "aura blacklist vs hidden aura", "exclusive filter vs blacklist",
        "dispellable debuffs vs all debuffs",
    },
    roleTrack = {
        "what should tanks track", "what should tank track",
        "what should dps track", "what should damage dealers track",
        "what should healers track", "what should healer track",
    },
    whyUse = {
        "why does range fade matter", "why does focus frame matter",
        "why use target of target", "why use boss frames",
        "why use focus kick tracker", "why use aura filters",
    },
    auraPlacement = {
        "which frame should show debuffs", "where should debuffs show",
        "which frame should show buffs", "where should buffs show",
        "where should auras show",
    },
    minimal = {
        "i want a minimal ui", "minimal ui", "minimal interface",
        "clean minimal ui", "simple ui", "simple interface",
    },
    overload = {
        "too much information", "too much info", "information overload",
        "i only want important info", "i only want important information",
        "i want fewer icons", "fewer icons", "reduce aura spam", "aura spam",
        "reduce buff spam", "reduce debuff spam",
    },
    recommendationFollowup = {
        "can you explain your recommendation", "explain your recommendation",
        "why that recommendation", "why this recommendation",
        "yes but safer", "safer please", "ok do first step",
        "do the first safe step", "apply first checklist item",
        "open first page from checklist", "skip this", "next recommendation",
    },
    subjectiveAura = {
        "useless", "important", "less noisy", "too noisy", "noisy",
        "less cluttered", "cluttered", "declutter", "decluttered",
        "clean up buffs", "clean up debuffs", "clean up auras",
    },
    aura = {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    },
    action = {
        "hide", "show", "make", "set", "change", "filter", "only",
    },
    vagueTarget = {
        "make target important", "prioritize target", "make focus important",
        "prioritize focus", "make boss important", "prioritize boss",
    },
}

A.RouterSafePlanningReply = function(title, body, examples, actions)
    A.RouterClearPendingResultsForRoute()
    A.lastAssistantPlanningContext = {
        title = tostring(title or "Safe planning guidance"),
        examples = tostring(examples or "guided setup; run checks; open player."),
        actions = tostring(actions or "Guided Setup | Run Checks | Open Player"),
    }
    return {
        text = tostring(title or "Safe planning guidance") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "guided setup; run checks; open player.") .. "\nYou can ask: " .. tostring(actions or "Guided Setup | Run Checks | Open Player"),
        status = "info",
        summary = "Assistant safe planning guidance",
    }
end

A.RouterSafePlanningFollowupTerms = A.RouterSafePlanningFollowupTerms or {
    examples = {
        "examples", "example", "show examples", "show me examples",
        "give examples", "what should i type", "what can i type",
        "what can i say", "show commands", "show me commands",
    },
    open = {
        "open it", "open that", "open this", "open the page",
        "open first page", "open the first page", "open first page from checklist",
        "take me there", "go there", "show it", "show that", "show this",
    },
    details = {
        "explain more", "tell me more", "more details", "details",
        "why", "why this", "why that", "explain it", "explain that",
        "can you explain that", "can you explain more",
    },
    safe = {
        "which one is safer", "what is safest", "what is safer",
        "safer please", "yes but safer", "safe option", "safe step",
    },
    apply = {
        "do it", "do that", "run it", "run that", "apply it", "apply that",
        "make it happen", "ok do first step", "do first safe step",
        "do the first safe step", "apply first example", "apply the first example",
        "apply first checklist item", "use first example", "use the first example",
    },
}

A.RouterTrySafePlanningFollowup = function(text, coreHandler)
    local ctx = type(A.lastAssistantPlanningContext) == "table" and A.lastAssistantPlanningContext or nil
    if not ctx then return nil end
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if R.ContainsAny(norm, R.CORRECTION_UNDO_TERMS) or R.ContainsAny(norm, R.CORRECTION_REDO_TERMS) then return nil end
    if R.ContainsAny(norm, {
        "why did that fail", "why did it fail", "why did this fail",
        "that did not work", "that didnt work", "that didn't work",
        "it did not work", "it didnt work", "it didn't work",
        "still broken", "still not working", "not fixed",
    }) then
        return nil
    end
    if (R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS))
        and R.ContainsAny(norm, R.EXPLICIT_DOMAIN_TERMS)
    then
        return nil
    end
    if (norm:match("^why%s+is%s+") or norm:match("^why%s+are%s+") or norm:match("^why%s+cant%s+") or norm:match("^why%s+can't%s+"))
        and R.ContainsAny(norm, R.EXPLICIT_DOMAIN_TERMS)
    then
        return nil
    end
    local terms = A.RouterSafePlanningFollowupTerms
    local title = tostring(ctx.title or "Safe planning guidance")
    local examples = tostring(ctx.examples or "guided setup; run checks; open player.")
    local actions = tostring(ctx.actions or "Guided Setup | Run Checks | Open Player")

    if R.ContainsAny(norm, terms.apply) then
        return {
            text = title .. "\nI will not apply a planning suggestion from a vague follow-up. Type one exact example command when you want a change, or ask me to open the page first.\nExamples: " .. examples,
            status = "info",
            summary = "Assistant planning guarded apply",
        }
    end

    if R.ContainsAny(norm, terms.examples) then
        return {
            text = title .. "\nExamples: " .. examples,
            status = "info",
            summary = "Assistant planning examples",
        }
    end

    if R.ContainsAny(norm, terms.open) then
        local command = R.FirstOpenActionCommand(actions)
        if command and type(coreHandler) == "function" then
            local result = coreHandler(command)
            if result and not A.RouterIsUnknownResult(result) then return result end
        end
        return {
            text = title .. "\nOpen one of these pages or actions: " .. actions,
            status = "info",
            summary = "Assistant planning navigation",
        }
    end

    if R.ContainsAny(norm, terms.safe) then
        return A.RouterSafePlanningReply(
            title,
            "The safest next step is navigation or inspection, not applying a vague change. Open the relevant page first, review the current option, then use one exact example command if you want a change.",
            examples,
            actions
        )
    end

    if R.ContainsAny(norm, terms.details) then
        return {
            text = title .. "\nUse the examples when you want a concrete change, or open the relevant page first if you want to inspect settings safely.\nExamples: " .. examples .. "\nYou can ask: " .. actions,
            status = "info",
            summary = "Assistant planning details",
        }
    end

    return nil
end

A.RouterTrySafePlanningShortcut = function(text, coreHandler)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    local terms = A.RouterSafePlanningTerms

    if R.ContainsAny(norm, terms.backup) then
        return A.RouterSafePlanningReply(
            "Profile backup planning",
            "Before broad UI work, export or copy the active profile. Export gives you a copyable profile string; copying creates another local profile to return to. I will not reset or overwrite a profile from a vague backup request.",
            "open profiles; export current profile; copy current profile to Raid Backup; profile status.",
            "Open Profiles | Export Current Profile | Profile Status"
        )
    end

    if R.ContainsAny(norm, terms.compare) then
        if R.ContainsAny(norm, { "range fade", "opacity", "alpha" }) then
            return A.RouterSafePlanningReply(
                "Range fade and opacity comparison",
                "Opacity is the normal transparency of a frame or element. Range Fade is conditional: it changes transparency when a unit is out of range. Use opacity for permanent visual weight; use Range Fade when you want out-of-range units to stand out or fade back.",
                "set raid range fade to 40; make party frames less transparent; open group health and text.",
                "Open Group Health & Text | Open Target | Open Bars"
            )
        end
        if R.ContainsAny(norm, { "class resource", "class resources", "power bar", "mana bar" }) then
            return A.RouterSafePlanningReply(
                "Resource bar comparison",
                "A power bar shows the main unit resource such as mana, energy, rage, focus, or runic power. Class Resources are class-specific counters or bars such as combo points, holy power, runes, soul shards, or arcane charges. Tune power bars for general resource readability; tune Class Resources for class mechanics.",
                "open class resources; detach target power bar; make class resources wider; set mana power bar color blue.",
                "Open Class Resources | Open Player | Open Colors"
            )
        end
        if R.ContainsAny(norm, { "focus kick", "focus kick tracker" }) then
            return A.RouterSafePlanningReply(
                "Cast bar and kick tracker comparison",
                "Cast bars show casts and channels on units such as Target, Focus, and Boss. The Focus Kick Tracker is a focused cast-bar helper for interrupt readiness. Use normal cast bars for broad cast visibility; use the Focus Kick Tracker when focus interrupts are central to your UI.",
                "open cast bars; show focus kick tracker; show kick ready on target; set target cast bar height to 24.",
                "Open Cast Bars | Explain Focus Kick Tracker | Explain Interrupt Ready"
            )
        end
        if R.ContainsAny(norm, { "target of target", "focus target" }) then
            return A.RouterSafePlanningReply(
                "Target-of-target and focus-target comparison",
                "Target of Target shows who your current target is targeting. Focus Target shows who your focus is targeting. Use Target of Target for tank/target awareness; use Focus Target when a focus unit matters for interrupts, PvP, or encounter tracking.",
                "open target of target; open focus target; show target of target; show focus target.",
                "Open Target of Target | Open Focus Target | Open Focus"
            )
        end
        if R.ContainsAny(norm, { "boss frame", "boss frames", "target frame" }) then
            return A.RouterSafePlanningReply(
                "Boss and target frame comparison",
                "Target is your current selected unit. Boss frames show encounter boss units even when they are not targeted. Use Target for immediate interaction; use Boss frames for encounter-wide awareness, boss casts, markers, and multi-boss tracking.",
                "open target; open boss frames; set boss cast bar height to 20; make target frame wider.",
                "Open Target | Open Boss Frames | Open Cast Bars"
            )
        end
        if R.ContainsAny(norm, { "raid marker", "raid markers", "role icon", "role icons", "ready check", "ready checks" }) then
            return A.RouterSafePlanningReply(
                "Group indicator comparison",
                "Raid markers identify a marked target or unit. Role icons show tank/healer/DPS roles. Ready-check icons show ready status before a pull. They all live around indicators, but they answer different questions: marked target, group role, or ready state.",
                "open group status and indicators; show raid ready check icon; show raid role icon; show raid marker on target.",
                "Open Group Status & Indicators | Open Target"
            )
        end
        if R.ContainsAny(norm, { "castbar", "cast bar" }) and R.ContainsAny(norm, { "unit frame", "unit frames" }) then
            return A.RouterSafePlanningReply(
                "Frame and cast bar comparison",
                "Unit frames show unit state such as health, power, name, portrait, range, and auras. Cast bars show casts and channels, including interrupt readability. Change unit frames for general layout; change cast bars when spell casts are hard to see.",
                "open target; open cast bars; set target width to 260; set target cast bar height to 24.",
                "Open Target | Open Cast Bars | Open Player"
            )
        end
        if R.ContainsAny(norm, { "unit frame", "unit frames", "group frame", "group frames" }) then
            return A.RouterSafePlanningReply(
                "Unit and group frame comparison",
                "Unit frames cover individual units such as Player, Target, Focus, Pet, Boss, Target of Target, and Focus Target. Group frames cover Party, Raid, and Mythic Raid members. Tune unit frames for the units you interact with; tune group frames for party and raid status.",
                "open player; open target; open group layout; open group health and text.",
                "Open Player | Open Target | Open Group Layout | Open Group Health & Text"
            )
        end
        if R.ContainsAny(norm, { "party", "raid", "mythic raid" }) then
            return A.RouterSafePlanningReply(
                "Group frame comparison",
                "Party frames are for small-group layouts; Raid and Mythic Raid frames are for larger grouped layouts. Use Party tuning for dungeons and small groups, Raid/Mythic Raid tuning for raid rosters, and copy settings only when you explicitly ask for that copy.",
                "open group layout; open group health and text; make party frames easier to read; make raid frames easier to read.",
                "Open Group Layout | Open Group Health & Text | Open Group Auras"
            )
        end
        if R.ContainsAny(norm, { "raid marker", "raid markers", "role icon", "role icons", "ready check", "ready checks" }) then
            return A.RouterSafePlanningReply(
                "Group indicator comparison",
                "Raid markers identify a marked target or unit. Role icons show tank/healer/DPS roles. Ready-check icons show ready status before a pull. They all live around indicators, but they answer different questions: marked target, group role, or ready state.",
                "open group status and indicators; show raid ready check icon; show raid role icon; show raid marker on target.",
                "Open Group Status & Indicators | Open Target"
            )
        end
        if R.ContainsAny(norm, { "absorb", "absorbs", "heal prediction", "incoming heal", "incoming heals" }) then
            return A.RouterSafePlanningReply(
                "Absorb and heal prediction comparison",
                "Absorbs are shields already preventing damage. Incoming heals or heal prediction show healing that is expected or already being cast. Use absorb displays for shields; use heal prediction when healers need to see likely future health.",
                "open bars; turn on heal prediction overlay; set absorb bar anchor right; set absorb bar color blue.",
                "Open Bars | Open Group Health & Text | Open Colors"
            )
        end
        if R.ContainsAny(norm, { "font outline", "font shadow" }) then
            return A.RouterSafePlanningReply(
                "Font outline and shadow comparison",
                "Font outline draws a hard edge around text; font shadow draws an offset shadow behind it. Use outline for maximum readability on busy frames, and shadow for softer contrast when the background is already calm.",
                "open fonts; set global font outline to outline; set shared shadow strength to 1.",
                "Open Fonts"
            )
        end
        if R.ContainsAny(norm, { "cooldown swipe", "cooldown text", "stack text" }) then
            return A.RouterSafePlanningReply(
                "Aura text and cooldown comparison",
                "Cooldown swipe is the radial visual cooldown overlay on an icon. Cooldown text is the timer number. Stack text is the stack count. Use swipe for quick visual timing, cooldown text for exact seconds, and stack text for aura stack decisions.",
                "open auras; set target buff cooldown text size to 14; show target buff cooldown swipe; set target buff stack text size to 12.",
                "Open Auras | Open Aura Style | Open Colors"
            )
        end
        if R.ContainsAny(norm, { "growth direction", "anchor", "anchor point", "x offset", "y offset" }) then
            return A.RouterSafePlanningReply(
                "Positioning option comparison",
                "Anchor chooses what an element attaches to. X and Y offsets move it away from that anchor. Growth direction controls where repeated icons or groups add new entries. Set anchors first, then offsets, then growth direction.",
                "open auras; move target buffs right 5; set raid growth direction down; set ready check anchor top right.",
                "Open Auras | Open Group Layout | Open Group Status & Indicators"
            )
        end
        if R.ContainsAny(norm, { "menu scale", "ui scale", "wow ui scale", "msuf frame scale", "frame scale" }) then
            return A.RouterSafePlanningReply(
                "Scale option comparison",
                "Menu scale changes the MSUF options window. MSUF frame scale changes MSUF frames. WoW UI scale affects the broader game UI. Use menu scale when the menu is hard to use, frame scale when unit frames are too small, and WoW UI scale only when the whole interface needs adjustment.",
                "open dashboard scaling; set MSUF menu scale to 100; set MSUF frame scale to 100.",
                "Open Dashboard Scaling | Open Display & Recovery"
            )
        end
        if R.ContainsAny(norm, { "profile copy", "profile export", "profile import", "profile switch", "reset profile", "factory reset" }) then
            return A.RouterSafePlanningReply(
                "Profile action comparison",
                "Copy creates another local profile. Export creates a copyable profile string. Import loads settings from a string. Profile switch changes the active saved profile. Reset affects profile data; factory reset is broader recovery and stays guarded.",
                "open profiles; export current profile; copy current profile to Raid Backup; profile status.",
                "Open Profiles | Export Current Profile | Profile Status"
            )
        end
        if R.ContainsAny(norm, { "edit mode", "unlock frames" }) then
            return A.RouterSafePlanningReply(
                "Edit Mode and unlock comparison",
                "MSUF Edit Mode is the safe layout tool for moving and previewing frames. Lock/unlock options control whether specific helpers can be moved or clicked. Use Edit Mode for overall frame placement; use lock options for individual movable helpers.",
                "enter edit mode; open edit mode; unlock combat timer; show frame previews.",
                "Open Edit Mode | Enter MSUF Edit Mode | Open Gameplay"
            )
        end
        if R.ContainsAny(norm, { "blizzard", "msuf frames", "msuf frame" }) then
            return A.RouterSafePlanningReply(
                "Blizzard and MSUF frame comparison",
                "Blizzard frames are WoW's default frames. MSUF frames are the addon-controlled replacements and helpers. If both appear, check Blizzard frame visibility/fallback options before changing MSUF layout.",
                "open miscellaneous; turn off blizzard unit frames; open group layout; run checks.",
                "Open Miscellaneous | Open Group Layout | Run Checks"
            )
        end
        if R.ContainsAny(norm, { "aura", "auras", "filter", "filters", "layout", "blacklist", "hidden aura", "hidden", "dispellable" }) then
            return A.RouterSafePlanningReply(
                "Aura system comparison",
                "Aura layout controls where icons appear, how they grow, size, spacing, text, and caps. Live Aura filters decide which buffs or debuffs are allowed, exclusive, raid-focused, or dispellable-focused. Saved exact blacklist data is read-only in the native 12.1 backend. Tune layout when icons look wrong; tune live filters when the wrong aura groups appear.",
                "open auras; open aura filters; show only dispellable debuffs; set target debuff raid filter on.",
                "Open Auras | Open Aura Filters | Check Target Buffs"
            )
        end
        if R.ContainsAny(norm, { "castbar", "cast bar", "unit frame", "unit frames" }) then
            return A.RouterSafePlanningReply(
                "Frame and cast bar comparison",
                "Unit frames show unit state such as health, power, name, portrait, range, and auras. Cast bars show casts and channels, including interrupt readability. Change unit frames for general layout; change cast bars when spell casts are hard to see.",
                "open target; open cast bars; set target width to 260; set target cast bar height to 24.",
                "Open Target | Open Cast Bars | Open Player"
            )
        end
    end

    if R.ContainsAny(norm, terms.roleTrack) then
        if R.ContainsAny(norm, { "healer", "healers", "healing", "heal" }) then
            return A.RouterSafePlanningReply(
                "Healer tracking guidance",
                "Healers usually need readable Party/Raid health, range fade, dispellable debuffs, incoming heals, important buffs/debuffs, ready checks, and enough cast-bar information for interrupts or dangerous casts.",
                "open group health and text; open group auras; show only dispellable debuffs; set raid range fade to 40.",
                "Open Group Health & Text | Open Group Auras | Open Aura Filters"
            )
        end
        if R.ContainsAny(norm, { "tank", "tanks", "tanking" }) then
            return A.RouterSafePlanningReply(
                "Tank tracking guidance",
                "Tanks usually need Target, Target of Target, Boss frames, boss/target casts, debuffs, raid markers, threat/status readability, and enough Party/Raid context for taunts, swaps, and externals.",
                "open target; open target of target; open boss frames; set target cast bar height to 24.",
                "Open Target | Open Target of Target | Open Boss Frames | Open Cast Bars"
            )
        end
        return A.RouterSafePlanningReply(
            "DPS tracking guidance",
            "DPS usually need Target and Focus readability, cast bars, class resources, important personal buffs/debuffs, enemy debuffs, interrupt feedback, and compact group context without clutter.",
            "open class resources; open cast bars; show focus kick tracker; set target debuff icon size to 30.",
            "Open Class Resources | Open Cast Bars | Open Aura Filters | Open Target"
        )
    end

    if R.ContainsAny(norm, terms.whyUse) then
        if R.ContainsAny(norm, { "range fade" }) then
            return A.RouterSafePlanningReply(
                "Why range fade matters",
                "Range Fade helps you notice when a unit is out of range without reading extra text. It is especially useful for healers and group frames because it can make unreachable players visually different.",
                "set raid range fade to 40; set party range fade to 40; open group health and text.",
                "Open Group Health & Text | Open Target"
            )
        end
        if R.ContainsAny(norm, { "target of target" }) then
            return A.RouterSafePlanningReply(
                "Why Target of Target matters",
                "Target of Target helps show who your current target is attacking or targeting. It is useful for tanks, assists, swaps, and checking whether a boss or enemy is targeting the expected unit.",
                "open target of target; show target of target; move target of target under target.",
                "Open Target of Target | Open Target"
            )
        end
        if R.ContainsAny(norm, { "boss frame", "boss frames" }) then
            return A.RouterSafePlanningReply(
                "Why Boss frames matter",
                "Boss frames keep encounter bosses visible even when you target something else. They are useful for multi-boss fights, boss casts, target highlights, markers, and raid mechanics.",
                "open boss frames; show boss frames; set boss cast bar height to 20.",
                "Open Boss Frames | Open Cast Bars"
            )
        end
        if R.ContainsAny(norm, { "focus kick", "focus kick tracker", "focus frame" }) then
            return A.RouterSafePlanningReply(
                "Why Focus and Focus Kick matter",
                "Focus keeps one important unit available without changing your target. Focus Kick Tracker makes interrupt-related focus casts easier to track, which helps in Mythic+, PvP, and fights with priority casts.",
                "open focus; open cast bars; show focus kick tracker; show kick ready on focus.",
                "Open Focus | Open Cast Bars"
            )
        end
        return A.RouterSafePlanningReply(
            "Why Aura Filters matter",
            "Aura Filters reduce noise by controlling which buffs and debuffs appear. They are safer than hiding whole aura systems because you can tune live filter tokens such as raid, player-only, exclusive, or dispellable while keeping important information visible. Saved exact SpellID/category blacklist data is read-only in the native 12.1 backend.",
            "open aura filters; show only dispellable debuffs; set target debuff raid filter on.",
            "Open Aura Filters | Open Auras | Check Target Buffs"
        )
    end

    if R.ContainsAny(norm, terms.auraPlacement) then
        return A.RouterSafePlanningReply(
            "Aura placement planning",
            "For most setups, Target and Focus should show important enemy debuffs and casts; Party/Raid should show healing-relevant debuffs, dispels, and critical group status; Player can show personal buffs and debuffs. Tell me the frame and aura type before I change visibility.",
            "open auras; open group auras; show only dispellable debuffs; set target debuff icon size to 30.",
            "Open Auras | Open Group Auras | Open Aura Filters"
        )
    end

    if R.ContainsAny(norm, terms.subjectiveAura)
        and R.ContainsAny(norm, terms.aura)
        and (R.ContainsAny(norm, terms.action) or R.ContainsAny(norm, { "noise", "clutter", "track" }))
    then
        return A.RouterSafePlanningReply(
            "Aura filter planning",
            "I will not guess which buffs or debuffs are useless or important, because that depends on class, content, and preference. The safe path is to inspect Aura Filters, then tune live filter tokens/toggles such as raid, player-only, exclusive, or dispellable. Saved exact SpellID/category blacklist data is read-only in the native 12.1 backend.",
            "open aura filters; show only dispellable debuffs; set target debuff raid filter on; set target debuff icon size to 30.",
            "Open Aura Filters | Open Auras | Check Target Buffs"
        )
    end

    if R.ContainsAny(norm, terms.overload) then
        return A.RouterSafePlanningReply(
            "Information density planning",
            "Reduce MSUF clutter by lowering aura counts first, then tuning aura filters, optional group status and indicators, and text density. I will not hide broad UI categories from a vague 'important info' request.",
            "open aura filters; set target buff icon count to 8; make raid frames easier to read; open group status and indicators.",
            "Open Aura Filters | Open Auras | Open Group Status & Indicators | Guided Setup"
        )
    end

    if R.ContainsAny(norm, { "less cluttered", "cluttered", "too noisy", "too busy", "clean this up", "clean that up", "clean it up" })
        and not R.ContainsAny(norm, { "player", "target", "focus", "boss", "party", "raid", "group", "aura", "auras", "buff", "buffs", "debuff", "debuffs", "cast", "castbar", "cast bar", "text" })
    then
        return A.RouterSafePlanningReply(
            "Clutter planning",
            "Name the MSUF area that feels cluttered before I change anything. Once the area is clear, I can reduce icon count, spacing, text size, aura filters, indicators, or cast-bar detail without guessing.",
            "make raid frames easier to read; make target buffs less noisy; open aura filters; open group status and indicators.",
            "Guided Setup | Open Aura Filters | Open Group Status & Indicators | What Can I Change Here"
        )
    end

    if R.ContainsAny(norm, terms.vagueTarget) then
        return A.RouterSafePlanningReply(
            "Priority frame planning",
            "Tell me what Target, Focus, or Boss signal should be more important: size, position, cast bar, debuffs, raid marker, range fade, or text. I can tune that exact MSUF area once it is named.",
            "make target frame wider; set target debuff icon size to 30; show focus kick tracker; open boss frames.",
            "Open Target | Open Focus | Open Boss Frames | Open Cast Bars"
        )
    end

    if R.ContainsAny(norm, terms.minimal) then
        return A.RouterSafePlanningReply(
            "Minimal UI planning",
            "For a minimal MSUF setup, start by keeping Player, Target, Focus, Cast Bars, and core Party/Raid information readable, then reduce aura counts and optional indicators. I will not hide broad systems from a vague minimal-ui request.",
            "guided setup; open aura filters; set target buff icon count to 8; open group status and indicators.",
            "Guided Setup | Open Aura Filters | Open Group Status & Indicators | Run Checks"
        )
    end

    if R.ContainsAny(norm, terms.diagnostic) then
        return A.RouterSafePlanningReply(
            "Diagnostic planning",
            "I can run local MSUF checks and explain likely causes, but I should not auto-change a whole profile from a vague diagnostic request. Start with checks, then apply one suggested fix at a time.",
            "run checks; why are target buffs hidden; why are party frames hidden; profile status.",
            "Run Checks | Profile Status | Open Display & Recovery"
        )
    end

    if R.ContainsAny(norm, terms.recommendationFollowup) then
        local ctx = type(A.lastAssistantPlanningContext) == "table" and A.lastAssistantPlanningContext or nil
        local title = ctx and ctx.title or "Recommendation guidance"
        local examples = ctx and ctx.examples or "guided setup; run checks; open group layout."
        local actions = ctx and ctx.actions or "Guided Setup | Run Checks | Open Group Layout"
        return A.RouterSafePlanningReply(
            title,
            "I will not apply a broad recommendation automatically. Use one exact example command, open the first relevant page, or run checks before changing settings. If this is a Guided Setup step, use 'next' or one listed example from the guide.",
            examples,
            actions
        )
    end

    if R.ContainsAny(norm, terms.checklist) then
        return A.RouterSafePlanningReply(
            "Setup checklist",
            "Check MSUF in this order: active profile, frame visibility, Player/Target size, Party/Raid layout, cast bars, aura filters, text readability, then recovery tools. This keeps broad UI work reversible and avoids changing unrelated settings.",
            "profile status; run checks; guided setup; open group layout.",
            "Run Checks | Guided Setup | Profile Status | Open Group Layout"
        )
    end

    if R.ContainsAny(norm, terms.automatic) then
        if R.ContainsAny(norm, {
            "healer", "healing", "heal", "tank", "tanking", "dps", "damage",
            "mythic plus", "mythic+", "m plus", "m+", "mplus", "dungeon", "dungeons",
            "raid", "raiding", "pvp", "arena", "arenas", "solo", "open world",
        }) then
            return nil
        end
        return A.RouterSafePlanningReply(
            "Safe setup planning",
            "I will not automatically rewrite your UI or apply broad defaults from one vague prompt. The safe path is Guided Setup or Run Checks, then one exact setting change at a time with undo available for normal Assistant changes.",
            "guided setup; run checks; make my UI better for healer; open dashboard scaling.",
            "Guided Setup | Run Checks | Open Dashboard Scaling | What Can I Change Here"
        )
    end

    return nil
end

R.SETUP_GUIDANCE_TERMS = {    "help me set up my ui", "help me setup my ui", "help me set up my interface",
    "help me setup my interface", "help me configure my frames", "help me configure unitframes",
    "help me configure unit frames", "help me build my ui", "help me build my layout",
    "i am new to unitframes", "i am new to unit frames", "im new to unitframes",
    "im new to unit frames", "new to unitframes", "new to unit frames",
    "what should i do first", "what should i change first", "where should i start",
    "make my ui better", "make my ui cleaner", "make my interface better",
    "make my interface cleaner", "clean up my ui", "clean up my interface",
    "make everything better", "fix my ui automatically", "start from scratch",
}

R.ROLE_RECOMMEND_TERMS = {    "recommend settings for healer", "recommend healer settings", "healer setup",
    "best healer settings", "settings for healer", "recommend settings for tank",
    "recommend tank settings", "tank setup", "best tank settings", "settings for tank",
    "recommend settings for dps", "recommend dps settings", "dps setup",
    "best dps settings", "settings for dps",
}

R.ROLE_RECOMMEND_INTENT_TERMS = {    "recommend", "recommendation", "recommendations", "best", "setup", "set up", "ui for", "interface for",
    "optimize", "optimise", "ui", "interface", "profile", "layout", "make", "create",
    "what should i change", "what should i configure", "what do i need",
    "how should i configure", "safe settings", "good settings",
    "make my ui better", "make my ui cleaner", "make my interface better", "make my interface cleaner",
    "clean up my ui", "clean up my interface",
}

R.ROLE_SELF_DESCRIPTION_TERMS = {    "i play", "i mainly", "i mostly", "i usually", "i am", "im", "i'm",
    "i want", "i need", "my main role", "my role", "as a",
}

R.ROLE_RECOMMEND_ROLE_TERMS = {    "healer", "healing", "heal", "tank", "tanking", "dps", "damage", "damage dealer", "dd",
    "heiler", "heilung", "schaden",
}

R.CONTENT_RECOMMEND_INTENT_TERMS = {    "recommend", "recommendation", "recommendations", "best", "setup", "set up",
    "optimize", "optimise",
    "ui setup", "interface setup", "ui layout", "interface layout", "layout setup",
    "configure", "configuration",
    "what should i change", "what should i configure", "what do i need",
    "how should i configure", "safe settings", "good settings",
    "make my ui better", "make my ui cleaner", "make my interface better", "make my interface cleaner",
    "clean up my ui", "clean up my interface",
}

R.CONTENT_SELF_DESCRIPTION_TERMS = {    "i play", "i mainly", "i mostly", "i usually", "i do", "i run",
    "i spend most", "mostly play", "mainly play", "mostly do", "mainly do",
}

R.CONTENT_RECOMMEND_CONTEXT_TERMS = {    "mythic plus", "mythic+", "m plus", "m+", "mplus", "keystone", "keystones", "dungeon", "dungeons",
    "raid", "raiding", "raid night", "mythic raid",
    "pvp", "arena", "arenas", "battleground", "battlegrounds", "rated battleground", "rated battlegrounds",
    "solo", "open world", "questing", "leveling", "levelling", "world content",
}

R.CLASS_GUIDANCE_INTENT_TERMS = {    "setup", "set up", "ui setup", "interface setup", "ui", "interface",
    "what should i change", "what should i configure", "what do i need",
    "how should i configure", "recommend", "recommendation", "recommendations",
    "i play", "i main", "i mostly play", "i mainly play", "class resource", "class resources",
    "make my ui better", "make my ui cleaner", "make my interface better", "make my interface cleaner",
}

R.CLASS_GUIDANCE_CLASSES = {    { key = "deathKnight", label = "Death Knight", terms = { "death knight", "blood death knight", "frost death knight", "unholy death knight" } },
    { key = "demonHunter", label = "Demon Hunter", terms = { "demon hunter", "havoc demon hunter", "vengeance demon hunter" } },
    { key = "druid", label = "Druid", terms = { "druid", "restoration druid", "guardian druid", "balance druid", "feral druid" } },
    { key = "evoker", label = "Evoker", terms = { "evoker", "preservation evoker", "augmentation evoker", "devastation evoker" } },
    { key = "hunter", label = "Hunter", terms = { "hunter", "beast mastery hunter", "marksmanship hunter", "survival hunter" } },
    { key = "mage", label = "Mage", terms = { "mage", "arcane mage", "fire mage", "frost mage" } },
    { key = "monk", label = "Monk", terms = { "monk", "mistweaver monk", "brewmaster monk", "windwalker monk" } },
    { key = "paladin", label = "Paladin", terms = { "paladin", "holy paladin", "protection paladin", "retribution paladin" } },
    { key = "priest", label = "Priest", terms = { "priest", "discipline priest", "holy priest", "shadow priest" } },
    { key = "rogue", label = "Rogue", terms = { "rogue", "assassination rogue", "outlaw rogue", "subtlety rogue" } },
    { key = "shaman", label = "Shaman", terms = { "shaman", "restoration shaman", "elemental shaman", "enhancement shaman" } },
    { key = "warlock", label = "Warlock", terms = { "warlock", "affliction warlock", "demonology warlock", "destruction warlock" } },
    { key = "warrior", label = "Warrior", terms = { "warrior", "arms warrior", "fury warrior", "protection warrior" } },
}

R.CLASS_GUIDANCE_HEALER_SPEC_TERMS = {    "restoration druid", "restoration shaman", "holy paladin", "holy priest",
    "discipline priest", "mistweaver monk", "preservation evoker",
}

R.CLASS_GUIDANCE_TANK_SPEC_TERMS = {    "blood death knight", "vengeance demon hunter", "guardian druid", "brewmaster monk",
    "protection paladin", "protection warrior",
}

R.RECOVERY_GUIDANCE_TERMS = {    "can you fix it", "fix it", "please fix this", "fix this", "fix that",
    "that did not work", "that didnt work", "it did not work", "it didnt work",
    "this did not work", "this didnt work", "it still does not work",
    "it still doesnt work", "still does not work", "still doesnt work",
    "still broken", "still not working", "not fixed",
    "why did that fail", "why did it fail", "why did this fail",
    "why that failed", "why it failed", "why this failed",
    "why this fix", "why that fix", "why the fix",
}

R.CONTEXTLESS_GUIDANCE_TERMS = {    "what now", "what should i do now", "i am confused", "im confused",
    "i dont understand", "i do not understand", "explain it simpler",
    "explain that", "explain it", "explain this", "which one should i pick",
    "which option should i choose", "which one should i choose",
    "open the right page", "show me where", "take me there",
    "open that", "open it", "go there",
    "explain option", "explain result", "open option", "open result",
    "choose option", "choose result", "select option", "select result",
    "what does option", "what does result", "option 1", "result 1",
    "do the safe thing", "choose for me",
}

function R.SetupGuidanceReply()    return {
        text = "Setup guidance\nStart with a clean baseline: readable Player and Target frames, visible Party/Raid frames, clear cast bars, and only then aura filters. I can walk you through it step by step.\nYou can ask: Guided Setup | Run Checks | Open Player | Open Group Layout",
        status = "info",
        summary = "Assistant setup guidance",
    }
end

function R.LooksLikeRoleGuidanceRequest(norm)    return R.ContainsAny(norm, R.ROLE_RECOMMEND_TERMS)
        or (R.ContainsAny(norm, R.ROLE_RECOMMEND_INTENT_TERMS) and R.ContainsAny(norm, R.ROLE_RECOMMEND_ROLE_TERMS))
        or (R.ContainsAny(norm, R.ROLE_SELF_DESCRIPTION_TERMS) and R.ContainsAny(norm, R.ROLE_RECOMMEND_ROLE_TERMS))
end

function R.LooksLikeContentGuidanceRequest(norm)    return (R.ContainsAny(norm, R.CONTENT_RECOMMEND_INTENT_TERMS) or R.ContainsAny(norm, R.CONTENT_SELF_DESCRIPTION_TERMS))
        and R.ContainsAny(norm, R.CONTENT_RECOMMEND_CONTEXT_TERMS)
end

function R.DetectGuidanceRole(norm)    norm = R.Normalize(norm)
    return R.ContainsAny(norm, { "healer", "healing", "heal", "heiler", "heilung" }) and "healer"
        or (R.ContainsAny(norm, { "tank", "tanking" }) and "tank")
        or (R.ContainsAny(norm, { "dps", "damage", "damage dealer", "dd", "schaden" }) and "dps")
        or nil
end

function R.DetectGuidanceContext(norm)    norm = R.Normalize(norm)
    return R.ContainsAny(norm, { "mythic plus", "mythic+", "m plus", "m+", "mplus", "keystone", "keystones", "dungeon", "dungeons" }) and "mythic+"
        or (R.ContainsAny(norm, { "pvp", "arena", "arenas", "battleground", "battlegrounds", "rated battleground", "rated battlegrounds" }) and "pvp")
        or (R.ContainsAny(norm, { "solo", "open world", "questing", "leveling", "levelling", "world content" }) and "solo")
        or (R.ContainsAny(norm, { "raid", "raiding", "raid night", "mythic raid" }) and "raid")
        or nil
end

function R.DetectGuidanceClass(norm)    norm = R.Normalize(norm)
    for i = 1, #R.CLASS_GUIDANCE_CLASSES do
        local spec = R.CLASS_GUIDANCE_CLASSES[i]
        if R.ContainsAny(norm, spec.terms) then return spec end
    end
    return nil
end

function R.DetectClassGuidanceRole(norm)    norm = R.Normalize(norm)
    if R.ContainsAny(norm, R.CLASS_GUIDANCE_HEALER_SPEC_TERMS) then return "healer" end
    if R.ContainsAny(norm, R.CLASS_GUIDANCE_TANK_SPEC_TERMS) then return "tank" end
    return R.DetectGuidanceRole(norm)
end

function R.LooksLikeClassGuidanceRequest(norm)    norm = R.Normalize(norm)
    if not R.DetectGuidanceClass(norm) then return false end
    if (R.LooksLikeMutation(norm) or R.StartsWithMutationCommand(norm))
        and not R.ContainsAny(norm, { "make my ui better", "make my ui cleaner", "make my interface better", "make my interface cleaner" })
    then
        return false
    end
    return R.ContainsAny(norm, R.CLASS_GUIDANCE_INTENT_TERMS)
end

function R.RoleGuidanceReply(text)    local norm = R.Normalize(text)
    local role = R.DetectGuidanceRole(norm) or "role"
    local detail, focus, examples, actions
    if role == "healer" then
        detail = "For healing, prioritize readable Party/Raid health text, dispel visibility, range fade, cast bars, and important buffs/debuffs."
        focus = "Start in Group Health & Text, Group Status & Indicators, Group Auras, and Cast Bars."
        examples = "turn on raid click casting; set raid range fade to 40; show only dispellable debuffs; set raid health text size to 14."
        actions = "Open Group Health & Text | Open Group Status & Indicators | Open Group Auras | Guided Setup"
    elseif role == "tank" then
        detail = "For tanking, prioritize Target, Target of Target, Boss frames, cast bars, debuffs, threat/status visibility, and clear health bars."
        focus = "Start in Target, Target of Target, Boss Frames, Cast Bars, and Group Status & Indicators."
        examples = "show target of target; make target cast bar height 24; open boss frames; show raid marker on target."
        actions = "Open Target | Open Target of Target | Open Boss Frames | Open Cast Bars"
    elseif role == "dps" then
        detail = "For DPS, prioritize Target, Focus, cast bars, class resources, important buffs/debuffs, and enough group visibility without clutter."
        focus = "Start in Target, Focus, Cast Bars, Class Resources, Aura Filters, and Group Layout."
        examples = "show focus kick tracker; show kick ready on target; open class resources; set target buff icon size to 30."
        actions = "Open Cast Bars | Open Class Resources | Open Aura Filters | Open Target"
    else
        detail = "For role setup, start with visibility, readable text, cast bars, and only the aura information you actively use."
        focus = "Start with Player/Target readability, group visibility, cast bars, and aura filters."
        examples = "guided setup; run checks; open player; open group layout."
        actions = "Guided Setup | Run Checks | Open Player | Open Group Layout"
    end
    return {
        text = "Role setup guidance\n" .. detail .. "\nSuggested MSUF focus: " .. focus .. "\nExamples: " .. examples .. "\nI will not guess-change your profile without a concrete request. Ask for Guided Setup, Run Checks, or name one exact change.\nYou can ask: " .. actions,
        status = "info",
        summary = "Assistant role setup guidance",
    }
end

function R.ClassGuidanceReply(text)    local norm = R.Normalize(text)
    if not R.LooksLikeClassGuidanceRequest(norm) then return nil end
    local classSpec = R.DetectGuidanceClass(norm)
    if not classSpec then return nil end

    local role = R.DetectClassGuidanceRole(norm)
    local label = classSpec.label
    local title = label .. " UI guidance"
    local detail, focus, examples, actions

    if classSpec.key == "rogue" then
        detail = "For Rogue UI, prioritize Class Resources, Target/Focus cast bars, important buffs/debuffs, and compact group visibility."
        focus = "Start in Class Resources, Cast Bars, Aura Filters, Target, and Focus."
        examples = "open class resources; show focus kick tracker; set target debuff icon size to 30."
        actions = "Open Class Resources | Open Cast Bars | Open Aura Filters"
    elseif classSpec.key == "shaman" then
        detail = "For Shaman UI, prioritize the Totem/Statue frame, Class Resources, Target/Focus cast bars, important buffs/debuffs, and group status if you heal."
        focus = "Start in Gameplay, Class Resources, Cast Bars, Aura Filters, and Group Health & Text."
        examples = "show totem frame; make totem icons bigger; open class resources; set target debuff icon size to 30."
        actions = "Open Gameplay | Open Class Resources | Open Cast Bars | Open Aura Filters"
    elseif role == "healer" then
        detail = "For " .. label .. " healing UI, prioritize readable Party/Raid frames, dispel visibility, range fade, cast bars, important auras, and Class Resources where MSUF exposes them."
        focus = "Start in Group Health & Text, Group Status & Indicators, Group Auras, Aura Filters, Cast Bars, and Class Resources."
        examples = "set raid range fade to 40; show only dispellable debuffs; set raid health text size to 14; open class resources."
        actions = "Open Group Health & Text | Open Group Status & Indicators | Open Group Auras | Open Class Resources"
    elseif role == "tank" then
        detail = "For " .. label .. " tank UI, prioritize Target, Target of Target, Boss frames, cast bars, debuffs, threat/status readability, and Class Resources where MSUF exposes them."
        focus = "Start in Target, Target of Target, Boss Frames, Cast Bars, Aura Filters, and Class Resources."
        examples = "show target of target; open boss frames; set target cast bar height to 24; open class resources."
        actions = "Open Target | Open Target of Target | Open Boss Frames | Open Cast Bars"
    else
        detail = "For " .. label .. " UI, prioritize Player/Target readability, Cast Bars, Class Resources, important buffs/debuffs, and enough group visibility for the content you play."
        focus = "Start in Player, Target, Cast Bars, Class Resources, Aura Filters, and Group Layout."
        examples = "open class resources; open cast bars; set target debuff icon size to 30; open aura filters."
        actions = "Open Class Resources | Open Cast Bars | Open Aura Filters | Open Target"
    end

    return {
        text = title .. "\n" .. detail .. "\nSuggested MSUF focus: " .. focus .. "\nExamples: " .. examples .. "\nI will not give live talent or rotation advice offline, but I can help tune the MSUF UI for this class.\nYou can ask: " .. actions,
        status = "info",
        summary = "Assistant class setup guidance",
    }
end

function R.ContentGuidanceReply(text)    local norm = R.Normalize(text)
    local context = R.DetectGuidanceContext(norm) or "raid"

    local detail, focus, examples, actions
    if context == "mythic+" then
        detail = "For Mythic+ and dungeon UI, prioritize Target/Focus cast bars, interrupts, boss frames, Party readability, dispel visibility, and important buffs/debuffs."
        focus = "Start in Cast Bars, Group Health & Text, Group Auras, Aura Filters, Target, and Focus."
        examples = "show focus kick tracker; show kick ready on target; set party range fade to 40; set target debuff icon size to 30."
        actions = "Open Cast Bars | Open Group Health & Text | Open Group Auras | Open Aura Filters"
    elseif context == "pvp" then
        detail = "For PvP UI, prioritize Target, Focus, cast bars, class resources, key debuffs, trinket-adjacent visibility, and clean group frames without hiding critical text."
        focus = "Start in Target, Focus, Cast Bars, Class Resources, Aura Filters, and Group Status & Indicators."
        examples = "show focus kick tracker; show kick ready on focus; open aura filters; make class resources wider."
        actions = "Open Cast Bars | Open Focus | Open Aura Filters | Open Class Resources"
    elseif context == "solo" then
        detail = "For solo and open-world UI, prioritize readable Player/Target frames, class resources, simple cast bars, Combat Timer, and only the auras you actively track."
        focus = "Start in Player, Target, Class Resources, Gameplay, Cast Bars, and Aura Filters."
        examples = "open player; open class resources; show combat timer; set target buff icon size to 28."
        actions = "Open Player | Open Target | Open Class Resources | Open Gameplay"
    else
        detail = "For raid UI, prioritize Raid/Mythic Raid layout, health text, range fade, dispel visibility, ready checks, boss frames, and boss cast bars."
        focus = "Start in Group Layout, Group Health & Text, Group Status & Indicators, Group Auras, Boss Frames, and Cast Bars."
        examples = "set raid range fade to 40; show raid ready check icon; open boss frames; set boss cast bar height to 20."
        actions = "Open Group Layout | Open Group Health & Text | Open Group Status & Indicators | Open Boss Frames"
    end

    return {
        text = "Content setup guidance\n" .. detail .. "\nSuggested MSUF focus: " .. focus .. "\nExamples: " .. examples .. "\nI will not guess-change your profile without a concrete request. Ask for Guided Setup, Run Checks, or name one exact change.\nYou can ask: " .. actions,
        status = "info",
        summary = "Assistant content setup guidance",
    }
end

function R.CombinedGuidanceReply(text)    local norm = R.Normalize(text)
    local broadSetupMutation = R.ContainsAny(norm, R.SETUP_GUIDANCE_TERMS)
        or norm:match("^make%s+.+%s+ui%s+better") ~= nil
        or norm:match("^make%s+.+%s+ui%s+cleaner") ~= nil
        or norm:match("^make%s+.+%s+interface%s+better") ~= nil
        or norm:match("^make%s+.+%s+interface%s+cleaner") ~= nil
    if (R.LooksLikeMutation(norm) or R.StartsWithMutationCommand(norm)) and not broadSetupMutation then return nil end
    local role = R.DetectGuidanceRole(norm)
    local context = R.DetectGuidanceContext(norm)
    if not role or not context then return nil end

    local title = "Combined setup guidance"
    local detail, focus, examples, actions

    if role == "healer" and context == "mythic+" then
        detail = "For Mythic+ healing, prioritize Party health clarity, dispel visibility, range fade, Target/Focus cast feedback, and important buffs/debuffs."
        focus = "Start in Group Health & Text, Group Auras, Cast Bars, Aura Filters, and Focus."
        examples = "turn on party click casting; set party range fade to 40; show only dispellable debuffs; show focus kick tracker."
        actions = "Open Group Health & Text | Open Group Auras | Open Cast Bars | Open Aura Filters"
    elseif role == "healer" and context == "raid" then
        detail = "For raid healing, prioritize Raid/Mythic Raid health text, range fade, dispel overlays, debuff visibility, ready checks, and auras that affect healing decisions."
        focus = "Start in Group Layout, Group Health & Text, Group Status & Indicators, and Group Auras."
        examples = "set raid range fade to 40; set raid health text size to 14; show raid ready check icon; show only dispellable debuffs."
        actions = "Open Group Layout | Open Group Health & Text | Open Group Status & Indicators | Open Group Auras"
    elseif role == "tank" and context == "mythic+" then
        detail = "For Mythic+ tanking, prioritize Target, Target of Target, Boss frames, interrupt feedback, debuff tracking, and readable Party status."
        focus = "Start in Target, Target of Target, Boss Frames, Cast Bars, and Group Health & Text."
        examples = "show target of target; make target cast bar height 24; show kick ready on target; set party range fade to 40."
        actions = "Open Target | Open Target of Target | Open Cast Bars | Open Group Health & Text"
    elseif role == "tank" and context == "raid" then
        detail = "For raid tanking, prioritize Boss frames, Target/Target of Target, raid markers, cast bars, debuffs, and enough Raid visibility for swaps and externals."
        focus = "Start in Boss Frames, Target, Target of Target, Cast Bars, Group Status & Indicators, and Group Health & Text."
        examples = "open boss frames; show target of target; show raid marker on target; set boss cast bar height to 20."
        actions = "Open Boss Frames | Open Target | Open Target of Target | Open Cast Bars"
    elseif role == "dps" and context == "mythic+" then
        detail = "For Mythic+ DPS, prioritize Target/Focus cast bars, interrupt-ready feedback, class resources, important debuffs, and compact Party awareness."
        focus = "Start in Cast Bars, Class Resources, Target, Focus, Aura Filters, and Group Health & Text."
        examples = "show focus kick tracker; show kick ready on target; open class resources; set target debuff icon size to 30."
        actions = "Open Cast Bars | Open Class Resources | Open Aura Filters | Open Focus"
    elseif role == "dps" and context == "raid" then
        detail = "For raid DPS, prioritize Boss frames, cast bars, class resources, Target/Focus readability, important debuffs, and lighter Raid visibility."
        focus = "Start in Boss Frames, Cast Bars, Class Resources, Target, Focus, and Aura Filters."
        examples = "open boss frames; show kick ready on target; open class resources; set target debuff icon size to 30."
        actions = "Open Boss Frames | Open Cast Bars | Open Class Resources | Open Aura Filters"
    elseif context == "pvp" then
        detail = "For PvP with this role, prioritize Target and Focus readability, cast bars, class resources, key debuffs, interrupt feedback, and compact group status."
        focus = "Start in Target, Focus, Cast Bars, Class Resources, Aura Filters, and Group Status & Indicators."
        examples = "show focus kick tracker; show kick ready on focus; open aura filters; make class resources wider."
        actions = "Open Focus | Open Cast Bars | Open Aura Filters | Open Class Resources"
    elseif context == "solo" then
        detail = "For solo play with this role, prioritize readable Player/Target frames, class resources, simple cast bars, Combat Timer, and a small set of useful auras."
        focus = "Start in Player, Target, Class Resources, Cast Bars, Gameplay, and Aura Filters."
        examples = "open player; open class resources; show combat timer; set target buff icon size to 28."
        actions = "Open Player | Open Target | Open Class Resources | Open Gameplay"
    else
        return nil
    end

    return {
        text = title .. "\n" .. detail .. "\nSuggested MSUF focus: " .. focus .. "\nExamples: " .. examples .. "\nI will not guess-change your profile without a concrete request. Ask for Guided Setup, Run Checks, or name one exact change.\nYou can ask: " .. actions,
        status = "info",
        summary = "Assistant combined setup guidance",
    }
end

function R.RecoveryGuidanceReply()    return {
        text = "Recovery guidance\nI can help, but I need the broken MSUF area before I apply a fix. Tell me what is still wrong, or let me run local checks.\nGood next prompts: Run Checks | why are target buffs hidden | why are party frames hidden | why is target cast bar hidden | undo",
        status = "info",
        summary = "Assistant recovery guidance",
    }
end

function R.ContextlessGuidanceReply()    return {
        text = "I need a little more MSUF context before I choose or open something. Name the area, page, setting, or result number you mean.\nUseful next prompts: Guided Setup | Run Checks | Open Auras | Open Cast Bars | explain result 1 | why are target buffs hidden",
        status = "info",
        summary = "Assistant context guidance",
    }
end

function R.TryPageHelpShortcut(text, coreHandler)    if type(coreHandler) ~= "function" then return nil end
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if not R.ContainsAny(norm, { "here", "this page", "current page", "page help" }) then return nil end
    if not R.ContainsAny(norm, {
        "help", "commands", "what can", "what settings", "explain",
        "how can", "how do", "how to", "where can", "where do",
    }) then
        return nil
    end
    local result = coreHandler(text)
    if result and not A.RouterIsUnknownResult(result) then return result end
    return nil
end

R.PAGE_LOCATION_INTENT_TERMS = {    "where is", "where are", "where do i find", "where can i find", "where to find",
    "where is the", "where are the", "where do i open", "where can i open",
}

R.PAGE_LOCATION_TERMS = {    { label = "Support Links", terms = { "support link", "support links", "support", "donate links", "development links", "discord link", "github link", "patreon link" } },
    { label = "Changelog", terms = { "changelog", "change log", "release notes", "latest changes", "build notes" } },
    { label = "Dashboard Scaling", terms = { "dashboard scaling", "dashboard scale", "scaling tools", "scale tools", "ui scale tools", "menu scale", "menu scaling", "msuf frame scale", "options scale" } },
    { label = "Display Recovery", terms = { "display recovery", "display and recovery", "recovery tools", "dashboard recovery", "recover menu", "reset tools" } },
    { label = "Group Health & Text", terms = { "group health and text", "group health text", "group text", "party health text", "raid health text", "mythic raid health text" } },
    { label = "Group Status & Indicators", terms = { "group status and indicators", "group indicators", "group indicator", "ready check", "ready checks", "role icon", "raid marker", "corner indicator", "corner indicators" } },
    { label = "Group Auras", terms = { "group aura", "group auras", "party auras", "raid auras", "mythic raid auras", "group buffs", "group debuffs", "party buffs", "party debuffs", "raid buffs", "raid debuffs" } },
    { label = "Group Layout", terms = { "group layout", "group frames", "party frames", "raid frames", "mythic raid frames", "party layout", "raid layout" } },
    { label = "Target of Target", terms = { "target of target", "targettarget" } },
    { label = "Focus Target", terms = { "focus target", "focustarget" } },
    { label = "Boss Frames", terms = { "boss frame", "boss frames", "bosses" } },
    { label = "Cast Bars", terms = { "cast bar", "cast bars", "castbar", "castbars", "boss casts", "target casts", "focus casts" } },
    { label = "Class Resources", terms = { "class power", "class powers", "class resource", "class resources", "combo point", "combo points", "holy power" } },
    { label = "Aura Filters", terms = { "aura filter", "aura filters", "hidden auras", "blacklist", "whitelist" } },
    { label = "Aura Style", terms = { "aura style", "aura styling", "aura cooldown text", "aura stack text" } },
    { label = "Aura Buffs", terms = { "aura buff", "aura buffs", "unit buff", "unit buffs", "target buff", "target buffs", "player buff", "player buffs", "focus buff", "focus buffs" } },
    { label = "Aura Debuffs", terms = { "aura debuff", "aura debuffs", "unit debuff", "unit debuffs", "target debuff", "target debuffs", "player debuff", "player debuffs", "focus debuff", "focus debuffs" } },
    { label = "Auras", terms = { "aura", "auras", "buff", "buffs", "debuff", "debuffs" } },
    { label = "Miscellaneous", terms = { "misc", "miscellaneous", "tooltip", "tooltips", "minimap", "menu language", "blizzard frames" } },
    { label = "Modules", terms = { "module", "modules", "advanced", "style module", "msuf style", "dropdown style" } },
    { label = "Gameplay", terms = { "gameplay", "combat timer", "combat crosshair", "totem frame", "totem", "totems", "statue frame" } },
    { label = "Profiles", terms = { "profile", "profiles", "profile import", "profile export", "spec profiles" } },
    { label = "Player", terms = { "player", "player frame", "self frame" } },
    { label = "Target", terms = { "target", "target frame" } },
    { label = "Focus", terms = { "focus", "focus frame" } },
    { label = "Pet", terms = { "pet", "pet frame" } },
    { label = "Bars", terms = { "bar", "bars", "bar texture", "bar textures", "absorb bar", "dispel overlay", "rounded bars", "aggro role filter", "aggro shows for", "highlight priority", "custom highlight priority" } },
    { label = "Colors", terms = { "color", "colors", "class colors", "bar colors", "font color" } },
    { label = "Fonts", terms = { "font", "fonts", "font outline", "font shadow" } },
}

function R.PageLocationLabelForText(norm)    norm = R.Normalize(norm)
    for i = 1, #R.PAGE_LOCATION_TERMS do
        local item = R.PAGE_LOCATION_TERMS[i]
        if R.ContainsAny(norm, item.terms) then return item.label end
    end
    return nil
end

function R.TryPageLocationShortcut(text, coreHandler)    if type(coreHandler) ~= "function" then return nil end
    local norm = R.Normalize(text)
    if norm == "" or not R.ContainsAny(norm, R.PAGE_LOCATION_INTENT_TERMS) then return nil end
    local label = R.PageLocationLabelForText(norm)
    if not label then return nil end
    local result = coreHandler("open " .. label)
    if result and not A.RouterIsUnknownResult(result) then
        result.status = result.status or result.result or "applied"
        return result
    end
    return nil
end

R.BROAD_PAGE_LOCATION_SUBJECTS = {
    ["profiles"] = true,
    ["profile"] = true,
    ["profile export"] = true,
    ["profile import"] = true,
    ["profile string"] = true,
    ["colors"] = true,
    ["color"] = true,
    ["colours"] = true,
    ["colour"] = true,
    ["group health and text"] = true,
    ["group health text"] = true,
    ["group health"] = true,
    ["aura filters"] = true,
    ["aura filter"] = true,
    ["cast bars"] = true,
    ["cast bar"] = true,
    ["castbars"] = true,
    ["castbar"] = true,
    ["bars"] = true,
    ["bar"] = true,
    ["fonts"] = true,
    ["font"] = true,
    ["gameplay"] = true,
    ["class resources"] = true,
    ["class resource"] = true,
    ["dashboard scaling"] = true,
    ["display recovery"] = true,
    ["modules"] = true,
    ["support links"] = true,
    ["changelog"] = true,
    ["group layout"] = true,
    ["group status and indicators"] = true,
    ["group indicators"] = true,
    ["group auras"] = true,
    ["auras"] = true,
    ["aura"] = true,
}

R.BROAD_SETTING_EXPLAIN_SUBJECTS = {
    ["global cooldown"] = true,
    ["gcd"] = true,
    ["a boss frame"] = true,
    ["boss frame"] = true,
    ["boss frames"] = true,
    ["a power bar"] = true,
    ["power bar"] = true,
    ["a health bar"] = true,
    ["health bar"] = true,
    ["alpha"] = true,
    ["opacity"] = true,
    ["an anchor point"] = true,
    ["a anchor point"] = true,
    ["anchor point"] = true,
    ["x offset"] = true,
    ["y offset"] = true,
    ["offset"] = true,
    ["scaling"] = true,
    ["scale"] = true,
    ["a texture"] = true,
    ["texture"] = true,
    ["textures"] = true,
    ["a bar texture"] = true,
    ["bar texture"] = true,
    ["bar textures"] = true,
    ["health bar texture"] = true,
    ["castbar texture"] = true,
    ["cast bar texture"] = true,
    ["font outline"] = true,
    ["cooldown swipe"] = true,
    ["stack text"] = true,
    ["growth direction"] = true,
    ["focus target"] = true,
    ["focustarget"] = true,
    ["target of target"] = true,
    ["targettarget"] = true,
    ["dispel"] = true,
    ["threat"] = true,
    ["aggro"] = true,
    ["range fade"] = true,
    ["this"] = true,
    ["that"] = true,
    ["it"] = true,
}

R.BROAD_CURRENT_VALUE_SUBJECTS = {
    ["width"] = true,
    ["height"] = true,
    ["size"] = true,
    ["scale"] = true,
    ["alpha"] = true,
    ["opacity"] = true,
    ["color"] = true,
    ["colour"] = true,
    ["font"] = true,
    ["font size"] = true,
    ["text size"] = true,
    ["texture"] = true,
    ["bar"] = true,
    ["bar height"] = true,
    ["bar width"] = true,
    ["castbar height"] = true,
    ["cast bar height"] = true,
    ["castbar width"] = true,
    ["cast bar width"] = true,
    ["frame height"] = true,
    ["frame width"] = true,
    ["icon"] = true,
    ["icon size"] = true,
    ["anchor"] = true,
    ["anchor point"] = true,
    ["x offset"] = true,
    ["y offset"] = true,
    ["offset"] = true,
    ["layer"] = true,
    ["spacing"] = true,
    ["growth"] = true,
    ["count"] = true,
    ["visibility"] = true,
    ["enabled"] = true,
}

function R.RegistryCurrentValueSubjectTooBroad(subject)
    subject = R.Normalize(subject)
    if subject == "" then return true end
    if R.BROAD_PAGE_LOCATION_SUBJECTS[subject] or R.BROAD_SETTING_EXPLAIN_SUBJECTS[subject] then return true end
    if R.BROAD_CURRENT_VALUE_SUBJECTS[subject] then return true end
    return false
end

function R.RegistryLocationSubject(norm)
    norm = R.Normalize(norm)
    local prefixes = {
        "where do i change ", "where can i change ", "where do i set ", "where can i set ",
        "where do i configure ", "where can i configure ", "where do i adjust ", "where can i adjust ",
        "where do i show ", "where can i show ", "where do i hide ", "where can i hide ",
        "where do i display ", "where can i display ",
        "where do i turn on ", "where can i turn on ", "where do i turn off ", "where can i turn off ",
        "where do i enable ", "where can i enable ", "where do i disable ", "where can i disable ",
        "can i turn on ", "can i turn off ", "can i enable ", "can i disable ",
        "can i show ", "can i hide ", "can i display ",
        "is there a way to turn on ", "is there a way to turn off ",
        "is there a way to enable ", "is there a way to disable ",
        "is there a way to show ", "is there a way to hide ", "is there a way to display ",
        "where do i find ", "where can i find ", "where is the ", "where is ",
        "which page has ", "what page has ", "which menu has ", "what menu has ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if norm:sub(1, #prefix) == prefix then
            norm = R.Trim(norm:sub(#prefix + 1))
            break
        end
    end
    norm = norm:gsub("^the%s+", "")
    return R.Trim(norm)
end

function R.LooksLikeBroadPageLocationQuestion(norm)
    local subject = R.RegistryLocationSubject(norm)
    if subject == "" then return false end
    return R.BROAD_PAGE_LOCATION_SUBJECTS[subject] == true
end

function R.LooksLikeRegistrySettingLocationQuestion(text)
    local norm = R.Normalize(text)
    if norm == "" or not R.AsksSettingLocation(norm) then return false end
    if A.RouterLooksLikeExplicitSearchRequest and A.RouterLooksLikeExplicitSearchRequest(norm) then return false end
    if R.LooksLikeBroadPageLocationQuestion(norm) then return false end
    if R.ContainsAny(norm, {
        "which setting", "what setting", "which option", "what option",
        "what controls", "which controls", "setting controls", "option controls",
        "where do i change", "where can i change", "where do i set", "where can i set",
        "where do i configure", "where can i configure", "where do i adjust", "where can i adjust",
        "where do i show", "where can i show", "where do i hide", "where can i hide",
        "where do i display", "where can i display",
        "where do i turn on", "where can i turn on", "where do i turn off", "where can i turn off",
        "where do i enable", "where can i enable", "where do i disable", "where can i disable",
        "can i turn on", "can i turn off", "can i enable", "can i disable",
        "can i show", "can i hide", "can i display",
        "is there a way to turn on", "is there a way to turn off",
        "is there a way to enable", "is there a way to disable",
        "is there a way to show", "is there a way to hide", "is there a way to display",
        "how do i change", "how can i change", "can i change",
        "how do i set", "how can i set", "can i set",
        "how do i configure", "how can i configure", "can i configure",
        "how do i adjust", "how can i adjust", "can i adjust",
        "which page has", "what page has", "which menu has", "what menu has",
        "where is the setting", "where is the option", "where is",
        "where do i find", "where can i find",
    }) then
        return true
    end
    return false
end

function R.RegistryExplainSubject(norm)
    norm = R.Normalize(norm)
    local prefixes = {
        "what does ", "what is ", "what are ",
        "explain ", "describe ", "tell me about ",
        "why would i use ", "why should i use ",
        "why would i change ", "why should i change ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if norm:sub(1, #prefix) == prefix then
            norm = R.Trim(norm:sub(#prefix + 1))
            break
        end
    end
    norm = norm:gsub("%s+do$", "")
    norm = norm:gsub("%s+control$", "")
    norm = norm:gsub("%s+controls$", "")
    norm = norm:gsub("%s+for$", "")
    norm = norm:gsub("^the%s+", "")
    return R.Trim(norm)
end

function R.RegistryCurrentValueSubject(norm)
    norm = R.Normalize(norm)
    local prefixes = {
        "current value of ", "current value for ",
        "current val of ", "current val for ",
        "curent value of ", "curent value for ",
        "curent val of ", "curent val for ",
        "show current value of ", "show current value for ",
        "show current val of ", "show current val for ",
        "show curent value of ", "show curent value for ",
        "show me current value of ", "show me current value for ",
        "show me current val of ", "show me current val for ",
        "show me curent value of ", "show me curent value for ",
        "show the current value of ", "show the current value for ",
        "show the current val of ", "show the current val for ",
        "show the curent value of ", "show the curent value for ",
        "show me the current value of ", "show me the current value for ",
        "show me the current val of ", "show me the current val for ",
        "show me the curent value of ", "show me the curent value for ",
        "get current value of ", "get current value for ",
        "get current val of ", "get current val for ",
        "get curent value of ", "get curent value for ",
        "get the current value of ", "get the current value for ",
        "get the current val of ", "get the current val for ",
        "get the curent value of ", "get the curent value for ",
        "what is the current value of ", "what is the current value for ",
        "what is the current val of ", "what is the current val for ",
        "what is the curent value of ", "what is the curent value for ",
        "what is current value of ", "what is current value for ",
        "what is current val of ", "what is current val for ",
        "what is curent value of ", "what is curent value for ",
        "what value is ", "what value does ",
        "what is the value of ", "what is the value for ",
        "what is ", "what are ", "what s ", "whats ",
        "is the ", "is ",
        "are the ", "are ",
        "do i have the ", "do i have ", "do we have the ", "do we have ",
        "do the ", "do ", "does the ", "does ", "will the ", "will ",
        "can i see the ", "can i see ", "can we see the ", "can we see ",
        "can i se the ", "can i se ", "can we se the ", "can we se ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if norm:sub(1, #prefix) == prefix then
            norm = R.Trim(norm:sub(#prefix + 1))
            break
        end
    end
    norm = norm:gsub("%s+set%s+to$", "")
    norm = norm:gsub("%s+currently%s+set%s+to$", "")
    norm = norm:gsub("%s+set%s+at$", "")
    norm = norm:gsub("%s+currently$", "")
    norm = norm:gsub("%s+right%s+now$", "")
    norm = norm:gsub("%s+turned%s+on$", "")
    norm = norm:gsub("%s+turned%s+off$", "")
    norm = norm:gsub("%s+turnd%s+on$", "")
    norm = norm:gsub("%s+turnd%s+off$", "")
    norm = norm:gsub("%s+turn%s+on$", "")
    norm = norm:gsub("%s+turn%s+off$", "")
    norm = norm:gsub("%s+switched%s+on$", "")
    norm = norm:gsub("%s+switched%s+off$", "")
    norm = norm:gsub("%s+switchd%s+on$", "")
    norm = norm:gsub("%s+switchd%s+off$", "")
    norm = norm:gsub("%s+show%s+right%s+now$", "")
    norm = norm:gsub("%s+shwo%s+right%s+now$", "")
    norm = norm:gsub("%s+show%s+now$", "")
    norm = norm:gsub("%s+shwo%s+now$", "")
    norm = norm:gsub("%s+show$", "")
    norm = norm:gsub("%s+shwo$", "")
    norm = norm:gsub("%s+shows$", "")
    norm = norm:gsub("%s+shwos$", "")
    norm = norm:gsub("%s+now$", "")
    norm = norm:gsub("%s+enabled$", "")
    norm = norm:gsub("%s+enabld$", "")
    norm = norm:gsub("%s+enabeld$", "")
    norm = norm:gsub("%s+disabled$", "")
    norm = norm:gsub("%s+disabld$", "")
    norm = norm:gsub("%s+disabeld$", "")
    norm = norm:gsub("%s+visible$", "")
    norm = norm:gsub("%s+visble$", "")
    norm = norm:gsub("%s+visibl$", "")
    norm = norm:gsub("%s+shown$", "")
    norm = norm:gsub("%s+shwon$", "")
    norm = norm:gsub("%s+showing$", "")
    norm = norm:gsub("%s+hidden$", "")
    norm = norm:gsub("%s+hiden$", "")
    norm = norm:gsub("%s+on$", "")
    norm = norm:gsub("%s+off$", "")
    norm = norm:gsub("^the%s+", "")
    return R.Trim(norm)
end

function R.LooksLikeRegistrySettingStateQuestion(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    if not (norm:match("^is%s+") or norm:match("^is%s+the%s+")
        or norm:match("^are%s+") or norm:match("^are%s+the%s+")
        or norm:match("^do%s+") or norm:match("^do%s+i%s+have%s+") or norm:match("^do%s+we%s+have%s+")
        or norm:match("^does%s+") or norm:match("^will%s+")
        or norm:match("^can%s+i%s+see%s+") or norm:match("^can%s+we%s+see%s+")
        or norm:match("^can%s+i%s+se%s+") or norm:match("^can%s+we%s+se%s+"))
    then
        return false
    end
    if not R.ContainsAny(norm, {
        "enabled", "disabled", "visible", "shown", "showing", "hidden",
        "turned on", "turned off", "switched on", "switched off", "on", "off",
        "show", "shows", "shwo", "shwos", "see", "se",
    }) then
        return false
    end
    if R.ContainsAny(norm, { "safe", "needed", "necessary", "recommended", "better", "good", "bad" }) then return false end
    return true
end

function R.RegistryCurrentValueExpectedBoolean(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, { "disabled", "hidden", "turned off", "turnd off", "turn off", "switched off", "switchd off", "off" }) then return false end
    if R.ContainsAny(norm, { "enabled", "visible", "shown", "showing", "turned on", "turnd on", "turn on", "switched on", "switchd on", "on" }) then return true end
    if R.LooksLikeRegistrySettingStateQuestion(norm)
        and (R.ContainsAny(norm, { "show", "shows", "shwo", "shwos" })
            or norm:match("^can%s+i%s+see%s+") or norm:match("^can%s+we%s+see%s+")
            or norm:match("^can%s+i%s+se%s+") or norm:match("^can%s+we%s+se%s+"))
    then
        return true
    end
    return nil
end

function R.LooksLikeRegistrySettingCurrentValueQuestion(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if A.RouterLooksLikeExplicitSearchRequest and A.RouterLooksLikeExplicitSearchRequest(norm) then return false end
    if norm == "current value" or norm == "value now" then return false end
    if R.ContainsAny(norm, {
        "current value of", "current value for",
        "current val of", "current val for",
        "curent value of", "curent value for",
        "curent val of", "curent val for",
        "show current value of", "show current value for",
        "show current val of", "show current val for",
        "show curent value of", "show curent value for",
        "show me current value of", "show me current value for",
        "show me current val of", "show me current val for",
        "show me curent value of", "show me curent value for",
        "show the current value of", "show the current value for",
        "show the current val of", "show the current val for",
        "show the curent value of", "show the curent value for",
        "show me the current value of", "show me the current value for",
        "show me the current val of", "show me the current val for",
        "show me the curent value of", "show me the curent value for",
        "get current value of", "get current value for",
        "get current val of", "get current val for",
        "get curent value of", "get curent value for",
        "get the current value of", "get the current value for",
        "get the current val of", "get the current val for",
        "get the curent value of", "get the curent value for",
        "what is the current value of", "what is the current value for",
        "what is the current val of", "what is the current val for",
        "what is the curent value of", "what is the curent value for",
        "what is current value of", "what is current value for",
        "what is current val of", "what is current val for",
        "what is curent value of", "what is curent value for",
        "what value is", "what is the value of", "what is the value for",
    }) then
        local subject = R.RegistryCurrentValueSubject(norm)
        if subject == "" then return false end
        if subject == "it" or subject == "that" or subject == "this" then return false end
        if subject:match("^result%s+%d+") or subject:match("^option%s+%d+") then return false end
        return true
    end
    if (norm:match("^what%s+is%s+") or norm:match("^what%s+are%s+") or norm:match("^what%s+s%s+") or norm:match("^whats%s+"))
        and R.ContainsAny(norm, { "set to", "set at", "currently", "right now" })
    then
        local subject = R.RegistryCurrentValueSubject(norm)
        if subject == "" or subject == norm then return false end
        if subject == "it" or subject == "that" or subject == "this" then return false end
        if subject:match("^result%s+%d+") or subject:match("^option%s+%d+") then return false end
        return true
    end
    if (norm:match("^is%s+") or norm:match("^is%s+the%s+") or norm:match("^are%s+") or norm:match("^are%s+the%s+"))
        and R.ContainsAny(norm, { "enabled", "disabled", "visible", "shown", "showing", "hidden", "on", "off" })
        and not R.ContainsAny(norm, { "safe", "needed", "necessary", "recommended", "better", "good", "bad" })
    then
        local subject = R.RegistryCurrentValueSubject(norm)
        if subject == "" or subject == norm then return false end
        if subject == "it" or subject == "that" or subject == "this" then return false end
        if subject:match("^result%s+%d+") or subject:match("^option%s+%d+") then return false end
        return true
    end
    if R.LooksLikeRegistrySettingStateQuestion(norm) then
        local subject = R.RegistryCurrentValueSubject(norm)
        if subject == "" or subject == norm then return false end
        if subject == "it" or subject == "that" or subject == "this" then return false end
        if subject:match("^result%s+%d+") or subject:match("^option%s+%d+") then return false end
        return true
    end
    return false
end

function R.LooksLikeRegistrySettingExplainQuestion(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if A.RouterLooksLikeExplicitSearchRequest and A.RouterLooksLikeExplicitSearchRequest(norm) then return false end
    if R.ContainsAny(norm, { "why are", "why is my", "why are my", "not showing", "missing", "doesnt work", "doesn't work" }) then return false end
    if not R.ContainsAny(norm, {
        "what does", "what is", "explain", "describe", "tell me about",
        "why would i use", "why should i use", "why would i change", "why should i change",
    }) then
        return false
    end
    local subject = R.RegistryExplainSubject(norm)
    if subject == "" then return false end
    if R.BROAD_PAGE_LOCATION_SUBJECTS[subject] then return false end
    if R.BROAD_SETTING_EXPLAIN_SUBJECTS[subject] then return false end
    if subject:find("where", 1, true) then return false end
    if subject:match("^result%s+%d+") or subject:match("^option%s+%d+") then return false end
    return true
end

function R.RegistryDecisionSubject(norm)
    norm = R.Normalize(norm)
    local prefixes = {
        "should i turn on ", "should i turn off ", "should i enable ", "should i disable ",
        "should i show ", "should i hide ", "should i use ", "should i keep ",
        "do i need to turn on ", "do i need to turn off ", "do i need to enable ", "do i need to disable ",
        "do i need to show ", "do i need to hide ", "do i need to use ",
        "do i need the ", "do i need ",
        "is it safe to turn on ", "is it safe to turn off ", "is it safe to enable ", "is it safe to disable ",
        "is it safe to show ", "is it safe to hide ", "is it safe to use ",
        "would it be safe to turn on ", "would it be safe to turn off ",
        "would it be safe to enable ", "would it be safe to disable ",
        "would it be safe to show ", "would it be safe to hide ", "would it be safe to use ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if norm:sub(1, #prefix) == prefix then
            norm = R.Trim(norm:sub(#prefix + 1))
            break
        end
    end
    norm = norm:gsub("^the%s+", "")
    return R.Trim(norm)
end

function R.LooksLikeRegistrySettingDecisionQuestion(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if A.RouterLooksLikeExplicitSearchRequest and A.RouterLooksLikeExplicitSearchRequest(norm) then return false end
    if not R.ContainsAny(norm, {
        "should i turn on", "should i turn off", "should i enable", "should i disable",
        "should i show", "should i hide", "should i use", "should i keep",
        "do i need", "do i need to",
        "is it safe to turn on", "is it safe to turn off", "is it safe to enable", "is it safe to disable",
        "is it safe to show", "is it safe to hide", "is it safe to use",
        "would it be safe to turn on", "would it be safe to turn off",
        "would it be safe to enable", "would it be safe to disable",
        "would it be safe to show", "would it be safe to hide", "would it be safe to use",
    }) then
        return false
    end
    local subject = R.RegistryDecisionSubject(norm)
    if subject == "" or subject == norm then return false end
    if subject:match("^result%s+%d+") or subject:match("^option%s+%d+") then return false end
    return true
end

function R.RegistryTroubleshootingSubject(norm)
    norm = R.Normalize(norm)
    local prefixes = {
        "why cant i see ", "why can't i see ", "why can t i see ", "why can i not see ",
        "why do i not see ", "why dont i see ", "why don't i see ", "why don t i see ",
        "why is my ", "why is the ", "why is ",
        "why are my ", "why are the ", "why are ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if norm:sub(1, #prefix) == prefix then
            norm = R.Trim(norm:sub(#prefix + 1))
            break
        end
    end
    local suffixes = {
        " not showing", " not shown", " not visible", " missing", " hidden",
        " gone", " invisible", " disabled", " turned off",
    }
    for i = 1, #suffixes do
        local suffix = suffixes[i]
        if norm:sub(-#suffix) == suffix then
            norm = R.Trim(norm:sub(1, #norm - #suffix))
            break
        end
    end
    norm = norm:gsub("^the%s+", "")
    return R.Trim(norm)
end

function R.IsBroadTroubleshootingSubject(subject)
    subject = R.Normalize(subject)
    if subject == "" then return true end
    local broad = {
        "player buffs", "target buffs", "focus buffs", "boss buffs", "party buffs", "raid buffs", "mythic raid buffs",
        "player debuffs", "target debuffs", "focus debuffs", "boss debuffs", "party debuffs", "raid debuffs", "mythic raid debuffs",
        "player cast bar", "target cast bar", "focus cast bar", "boss cast bar",
        "player castbar", "target castbar", "focus castbar", "boss castbar",
        "class resource", "class resources", "class power", "class powers",
        "frames", "unit frames", "unitframes", "profile", "profiles",
        "player frame", "target frame", "focus frame", "pet frame",
        "boss frame", "boss frames", "party frames", "raid frames",
        "group frame", "group frames", "mythic raid frames",
    }
    for i = 1, #broad do
        if subject == broad[i] then return true end
    end
    return false
end

function R.LooksLikeRegistrySettingTroubleshootingQuestion(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if A.RouterLooksLikeExplicitSearchRequest and A.RouterLooksLikeExplicitSearchRequest(norm) then return false end
    local asksWhyCantSee = R.ContainsAny(norm, {
        "why cant i see", "why can't i see", "why can t i see", "why can i not see",
        "why do i not see", "why dont i see", "why don't i see", "why don t i see",
    })
    if not (norm:match("^why%s+") ~= nil or asksWhyCantSee) then
        return false
    end
    if not asksWhyCantSee and not R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS) then return false end
    local subject = R.RegistryTroubleshootingSubject(norm)
    if subject == "" or subject == norm then return false end
    if R.IsBroadTroubleshootingSubject(subject) then return false end
    return true
end

function R.RegistryRequestedScope(norm)
    norm = R.Normalize(norm)
    local groupScope, groupLabel = R.GroupScopeFromText(norm)
    if groupScope then return "group", groupScope, groupLabel end
    local unit, unitLabel = R.UnitFrameScopeFromText and R.UnitFrameScopeFromText(norm) or R.UnitScopeFromText(norm)
    if unit then return "unit", unit, unitLabel end
    return nil, nil, nil
end

function R.RegistryItemScopeScore(item, scopeKind, scope, scopeLabel)
    if not scopeKind or not scope or type(item) ~= "table" then return 0 end
    local setting = item.setting or {}
    local hay = R.Normalize(table.concat({
        tostring(item.label or ""),
        tostring(item.pageLabel or ""),
        tostring(item.page or ""),
        tostring(item.key or ""),
        tostring(setting.key or ""),
        tostring(setting.unit or ""),
        tostring(setting.frameType or ""),
    }, " "))
    local score = 0
    if scopeKind == "unit" then
        if scope == "target" and R.ContainsAny(hay, { "target of target", "targettarget", "focus target", "focustarget" }) then return -800 end
        if scope == "focus" and R.ContainsAny(hay, { "focus target", "focustarget" }) then return -800 end
        if scope == "targettarget" and R.ContainsAny(hay, { "target of target", "targettarget" }) then score = score + 260 end
        if scope == "focustarget" and R.ContainsAny(hay, { "focus target", "focustarget" }) then score = score + 260 end
        if tostring(setting.unit or "") == scope then score = score + 260 end
        if R.ContainsAny(hay, { scope, tostring(scopeLabel or "") }) then score = score + 180 end
        if score == 0 then score = score - 120 end
    elseif scopeKind == "group" then
        if scope == "raid" and R.ContainsAny(hay, { "mythic raid", "mythicraid" }) then score = score - 260 end
        if tostring(setting.unit or "") == scope then score = score + 260 end
        if R.ContainsAny(hay, { scope, tostring(scopeLabel or "") }) then score = score + 180 end
        if score == 0 then score = score - 120 end
    end
    return score
end

function R.RegistryLocationResultFollowups(entries, limit)
    local out = {}
    limit = math.min(tonumber(limit) or 4, #(entries or {}))
    for i = 1, limit do
        local item = entries[i] and entries[i].item
        if item then
            out[#out + 1] = {
                kind = item.kind,
                key = item.key,
                label = item.label,
                page = item.page,
                pageLabel = item.pageLabel,
                category = item.category,
                description = item.description,
                controlType = item.controlType,
                settingKey = item.setting and item.setting.key,
                canOpen = item.canOpen,
                canExplain = item.canExplain,
            }
        end
    end
    return out
end

local GROUP_LAYOUT_FALLBACK_ATTRS = {
    enabled = true,
    showPlayer = true,
    showSolo = true,
    clickCast = true,
    clickCastEnabled = true,
    blizzardFallbackMode = true,
    hideInClientScene = true,
    hideOfflineEnabled = true,
    hideOfflineInCombat = true,
    hideOfflineDelay = true,
    smoothFill = true,
    reverseFill = true,
    groupBackdropColor = true,
    bgColor = true,
    width = true,
    height = true,
    offsetX = true,
    offsetY = true,
    spacing = true,
    unitsPerColumn = true,
    maxColumns = true,
    preserveRaidGroups = true,
    growth = true,
    sortMode = true,
    sortByRole = true,
    playerFirstInRole = true,
    roleOrder = true,
    frameScaleMode = true,
    frameScaleEnabled = true,
    frameScaleManual = true,
    scaleAt10 = true,
    scaleAt20 = true,
    scaleAt25 = true,
    scaleOver25 = true,
    anchorToFrame = true,
    customAnchorFrame = true,
    anchorPoint = true,
}

function R.FallbackPageForSetting(setting)
    if type(setting) ~= "table" then return nil end
    local unit = tostring(setting.unit or "")
    local frameType = tostring(setting.frameType or "")
    local category = R.Normalize(setting.category or "")
    local unitPages = {
        player = "uf_player",
        target = "uf_target",
        focus = "uf_focus",
        pet = "uf_pet",
        boss = "uf_boss",
        targettarget = "uf_targettarget",
        focustarget = "uf_focustarget",
    }
    if unitPages[unit] then return unitPages[unit] end
    if unit == "party" or unit == "raid" or unit == "mythicraid" then
        if frameType == "aura" then return "gf_auras" end
        local attr = tostring(setting.attribute or "")
        local key = tostring(setting.key or "")
        local compactAttr = R.Normalize(attr):gsub("%s+", "")
        local compactKey = R.Normalize(key):gsub("%s+", "")
        if category:find("indicator", 1, true)
            or compactAttr:find("targetedspells", 1, true)
            or compactKey:find("targetedspells", 1, true)
            or compactAttr:find("statusicon", 1, true)
            or compactKey:find("statusicon", 1, true)
            or compactAttr:find("roleicon", 1, true)
            or compactKey:find("roleicon", 1, true)
        then
            return "gf_indicators"
        end
        local suffix = tostring(setting.key or ""):match("%.([^%.]+)$")
        if GROUP_LAYOUT_FALLBACK_ATTRS[attr] or (suffix and GROUP_LAYOUT_FALLBACK_ATTRS[suffix]) then return "gf_layout" end
        return "gf_bars"
    end
    if category:find("misc", 1, true) then return "opt_misc" end
    if category:find("cast", 1, true) then return "castbars" end
    if category:find("aura", 1, true) then return "auras3" end
    return nil
end

function R.SettingFollowupResults(settingKey, query)
    settingKey = tostring(settingKey or "")
    if settingKey == "" then return nil end
    local registry = A.Registry
    local setting = registry and type(registry.GetSetting) == "function" and registry:GetSetting(settingKey) or nil
    query = tostring(query or (setting and setting.label) or settingKey)

    if A.Knowledge and type(A.Knowledge.Search) == "function" then
        local results = A.Knowledge.Search(query, 12, { kind = "setting", ignoreCurrentPage = true }) or {}
        for i = 1, #results do
            local item = results[i] and results[i].item
            local itemSetting = item and item.setting
            if tostring(itemSetting and itemSetting.key or item and item.settingKey or item and item.key or "") == settingKey then
                return R.RegistryLocationResultFollowups({ { item = item } }, 1)
            end
        end
    end

    if not setting then return nil end
    local page = R.FallbackPageForSetting(setting)
    local pageLabel = page and A.DisplayPageLabel and A.DisplayPageLabel(page, "MSUF page") or nil
    return {
        {
            kind = "setting",
            key = setting.key,
            settingKey = setting.key,
            label = setting.label,
            page = page,
            pageLabel = pageLabel,
            category = setting.category,
            controlType = setting.type,
            canOpen = page ~= nil,
            canExplain = true,
        },
    }
end

function R.SettingFollowupResultsByQuery(query, exactLabel)
    query = tostring(query or "")
    if query == "" or not (A.Knowledge and type(A.Knowledge.Search) == "function") then return nil end
    local results = A.Knowledge.Search(query, 12, { kind = "setting", ignoreCurrentPage = true }) or {}
    local exactNorm = R.Normalize(exactLabel or query)
    local first
    for i = 1, #results do
        local item = results[i] and results[i].item
        if item and item.kind == "setting" then
            first = first or item
            if exactNorm ~= "" and R.Normalize(item.label or "") == exactNorm then
                return R.RegistryLocationResultFollowups({ { item = item } }, 1)
            end
        end
    end
    if first then return R.RegistryLocationResultFollowups({ { item = first } }, 1) end
    return nil
end

function R.RegistrySettingExample(item)
    if type(item) ~= "table" then return nil end
    local setting = item.setting or {}
    local label = tostring(item.label or setting.label or "that setting")
    local kind = tostring(item.controlType or setting.type or "")
    if kind == "boolean" then return "turn on " .. label end
    if kind == "number" then
        local normLabel = R.Normalize(label)
        local value = tonumber(setting.default)
        if not value or value == 0 then value = tonumber(setting.min) end
        if not value or value == 0 then
            if R.ContainsAny(normLabel, { "font", "text size", "font size" }) then value = 14
            elseif R.ContainsAny(normLabel, { "width" }) then value = 250
            elseif R.ContainsAny(normLabel, { "height" }) then value = 40
            elseif R.ContainsAny(normLabel, { "range fade alpha", "range fade opacity" }) then value = 40
            elseif R.ContainsAny(normLabel, { "opacity", "alpha" }) then value = 80
            else value = 1 end
        end
        return "set " .. label .. " to " .. tostring(value)
    end
    if kind == "color" then return "set " .. label .. " to red" end
    if kind == "enum" then return "set " .. label .. " to one of its listed choices" end
    if kind == "string" then return "set " .. label .. " to the value you want" end
    return "open " .. tostring(item.pageLabel or "the matching page")
end

function R.RegistrySettingTypeText(controlType)
    controlType = tostring(controlType or "")
    if controlType == "" or controlType == "setting" then return "a setting" end
    local first = controlType:sub(1, 1):lower()
    local article = first:match("[aeiou]") and "an" or "a"
    return article .. " " .. controlType .. " setting"
end

function R.RegistryLocationLine(index, item)
    local label = tostring(item and item.label or "MSUF setting")
    local pageLabel = tostring(item and item.pageLabel or "MSUF page")
    local kind = tostring(item and item.controlType or "setting")
    return tostring(index) .. ". " .. label .. " - " .. pageLabel .. " [" .. kind .. "]"
end

function R.RegistryCloseMatchAllowed(item, queryNorm)
    local setting = item and item.setting or {}
    local hay = R.Normalize(table.concat({
        tostring(item and item.label or ""),
        tostring(item and item.key or ""),
        tostring(item and item.pageLabel or ""),
        tostring(setting.key or ""),
    }, " "))
    local groups = {
        { query = { "padding" }, item = { "padding" } },
        { query = { "font size", "text size" }, item = { "font size", "text size", "size" } },
        { query = { "border" }, item = { "border", "outline" } },
        { query = { "outline" }, item = { "outline", "border" } },
        { query = { "background", "backdrop" }, item = { "background", "backdrop" } },
        { query = { "preset", "blacklist" }, item = { "preset", "blacklist", "hidden aura" } },
    }
    for i = 1, #groups do
        local group = groups[i]
        if R.ContainsAny(queryNorm, group.query) and not R.ContainsAny(hay, group.item) then return false end
    end
    return true
end

function R.HasTargetTargetInlineSubject(norm)
    norm = R.Normalize(norm)
    return R.ContainsAny(norm, { "targettarget", "tot", "targets target" })
end

function R.HasTargetTargetInlineFrameContext(norm)
    norm = R.Normalize(norm)
    return R.ContainsAny(norm, {
        "target frame", "the target frame",
        "on target", "on the target", "on target frame", "on the target frame",
        "in target", "in the target", "in target frame", "in the target frame",
        "inside target", "inside the target", "inside target frame", "inside the target frame",
        "inline",
    })
end

function R.LooksLikeTargetTargetInlineNameRequest(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    if not R.HasTargetTargetInlineSubject(norm) then return false end
    if not R.HasTargetTargetInlineFrameContext(norm) then return false end
    if not R.ContainsAny(norm, { "name", "name text", "text" }) then return false end
    if R.ContainsAny(norm, { "health", "hp", "power", "mana", "font size", "text size", "bigger", "larger", "smaller" }) then return false end
    return true
end

function R.RegistrySettingSearchEntries(text, norm, limit)
    if not (A.Knowledge and type(A.Knowledge.Search) == "function") then return nil end
    local results = A.Knowledge.Search(text, tonumber(limit) or 16, { kind = "setting", ignoreCurrentPage = true }) or {}
    if #results == 0 then return nil end

    local scopeKind, scope, scopeLabel = R.RegistryRequestedScope(norm)
    local entries = {}
    for i = 1, #results do
        local item = results[i] and results[i].item
        if item and item.kind == "setting" then
            local setting = item.setting or {}
            local score = (tonumber(results[i].score) or 0) + R.RegistryItemScopeScore(item, scopeKind, scope, scopeLabel)
            if tostring(setting.key or item.key or "") == "targettarget.showToTInTargetName"
                and R.LooksLikeTargetTargetInlineNameRequest(norm)
            then
                score = score + 700
            end
            if score > 0 then entries[#entries + 1] = { item = item, score = score, rawScore = tonumber(results[i].score) or 0 } end
        end
    end
    if #entries == 0 then return nil end
    table.sort(entries, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.item and a.item.label or "") < tostring(b.item and b.item.label or "")
    end)
    return entries
end

function R.RegistryValueLabel(setting, value)
    if value == nil then return nil end
    if type(value) == "boolean" then return value and "enabled" or "disabled" end
    if type(value) == "table" then
        if type(value.label) == "string" and value.label ~= "" then return tostring(value.label) end
        local r = tonumber(value.r or value[1])
        local g = tonumber(value.g or value[2])
        local b = tonumber(value.b or value[3])
        if r and g and b then
            r = math.max(0, math.min(255, math.floor((r <= 1 and r * 255 or r) + 0.5)))
            g = math.max(0, math.min(255, math.floor((g <= 1 and g * 255 or g) + 0.5)))
            b = math.max(0, math.min(255, math.floor((b <= 1 and b * 255 or b) + 0.5)))
            return string.format("#%02X%02X%02X", r, g, b)
        end
        return "custom value"
    end
    if setting and (setting.type == "enum" or type(setting.values) == "table") and type(A.HumanizeDisplayKey) == "function" then
        return A.HumanizeDisplayKey(value)
    end
    return tostring(value)
end

function R.RegistryCurrentValueLine(item)
    local setting = item and item.setting
    if not setting or type(setting.get) ~= "function" then return nil end
    local value = setting.get()
    local label = R.RegistryValueLabel(setting, value)
    if label == nil or label == "" then return nil end
    return "Current value: " .. tostring(label) .. "."
end

function R.RegistrySettingPurpose(item)
    item = item or {}
    local setting = item.setting or {}
    local label = tostring(item.label or setting.label or "This MSUF setting")
    local normLabel = R.Normalize(label)
    local desc = item.description or setting.description or setting.summary
    if type(desc) == "string" and desc ~= "" then
        desc = R.Trim(desc)
        if desc:sub(-1) ~= "." then desc = desc .. "." end
        return desc
    end
    if R.ContainsAny(normLabel, { "font size", "text size" }) then return label .. " controls how large that text is drawn." end
    if R.ContainsAny(normLabel, { "spell name font size" }) then return label .. " controls the cast-bar spell-name text size." end
    if R.ContainsAny(normLabel, { "range fade alpha", "range fade opacity" }) then return label .. " controls how faded out-of-range frames become." end
    if R.ContainsAny(normLabel, { "range fade" }) then return label .. " controls whether frames fade when units are out of range." end
    if R.ContainsAny(normLabel, { "dead background color" }) then return label .. " controls the color used behind dead group members so they are easier to spot." end
    if R.ContainsAny(normLabel, { "background color", "backdrop color" }) then return label .. " controls the background color used by that frame or element." end
    if R.ContainsAny(normLabel, { "border padding" }) then return label .. " controls the spacing around the group border so the outline has room around the frames." end
    if R.ContainsAny(normLabel, { "border thickness", "outline" }) then return label .. " controls how thick the border or outline is." end
    if R.ContainsAny(normLabel, { "border" }) then return label .. " controls the border style around that visual element." end
    if R.ContainsAny(normLabel, { "hidden aura preset", "blacklist preset" }) then return label .. " applies a preset for hidden/blacklisted aura handling so common noisy auras can be filtered faster." end
    if R.ContainsAny(normLabel, { "health color scheme", "health color mode" }) then return label .. " chooses how MSUF colors the health bar, such as class coloring or another health-color mode." end
    local kind = tostring(item.controlType or setting.type or "setting")
    if kind == "boolean" then return label .. " turns that MSUF option on or off." end
    if kind == "number" then return label .. " changes the numeric amount for that MSUF option." end
    if kind == "color" then return label .. " sets the color used by that MSUF option." end
    if kind == "enum" then return label .. " chooses which mode or style MSUF uses for that option." end
    if kind == "string" then return label .. " stores the text, media name, or free-form value used by that option." end
    return label .. " is an MSUF setting on this area of the menu."
end

function R.RegistryEnumChoicesLine(item)
    local setting = item and item.setting
    if not setting or type(setting.values) ~= "table" or #setting.values == 0 or #setting.values > 8 then return nil end
    local values = {}
    for i = 1, #setting.values do
        local value = setting.values[i]
        values[#values + 1] = R.RegistryValueLabel(setting, value)
    end
    return "Choices: " .. table.concat(values, ", ") .. "."
end

R.LAST_CHANGE_VALUE_FOLLOWUP_TERMS = {
    "what is it now", "what is that now", "what is this now",
    "what is it set to", "what is that set to", "what is this set to",
    "what value is it", "what value is that", "what value is this",
    "current value", "value now", "what is the value",
    "is it on", "is that on", "is this on",
    "is it off", "is that off", "is this off",
    "is it enabled", "is that enabled", "is this enabled",
    "is it disabled", "is that disabled", "is this disabled",
}

R.LAST_CHANGE_LOCATION_FOLLOWUP_TERMS = {
    "where is it", "where is that", "where is this",
    "where do i change it", "where do i change that", "where do i change this",
    "where can i change it", "where can i change that", "where can i change this",
    "which page is it on", "which page is that on", "which page is this on",
    "what page is it on", "what page is that on", "what page is this on",
    "what menu is it in", "what menu is that in", "what menu is this in",
}

R.LAST_CHANGE_EXPLAIN_FOLLOWUP_TERMS = {
    "what does it do", "what does that do", "what does this do",
    "what does it mean", "what does that mean", "what does this mean",
    "explain it", "explain that", "explain this",
    "why should i use it", "why should i use that", "why should i use this",
    "why would i use it", "why would i use that", "why would i use this",
    "what is it for", "what is that for", "what is this for",
    "what does it help with", "what does that help with", "what does this help with",
}

function R.LastChangedSettingItem()
    local ctx = A.GetContext and A.GetContext() or nil
    local key = tostring(ctx and ctx.lastSetting or "")
    if key == "" and type(ctx and ctx.lastChangeBundle) == "table" then
        for i = #ctx.lastChangeBundle, 1, -1 do
            key = tostring(ctx.lastChangeBundle[i] and ctx.lastChangeBundle[i].key or "")
            if key ~= "" then break end
        end
    end
    if key == "" then return nil, ctx end

    local registry = A.Registry
    local setting = registry and type(registry.GetSetting) == "function" and registry:GetSetting(key) or nil
    if not setting then return nil, ctx end

    local page = setting.page or R.FallbackPageForSetting(setting)
    local pageLabel = page and A.DisplayPageLabel and A.DisplayPageLabel(page, "MSUF page") or nil
    local label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or tostring(setting.label or key)
    return {
        kind = "setting",
        key = key,
        settingKey = key,
        label = label,
        page = page,
        pageLabel = pageLabel,
        category = setting.category,
        controlType = setting.type,
        setting = setting,
        canOpen = page ~= nil,
        canExplain = true,
    }, ctx
end

function R.LastChangeFollowupHasSubject(norm)
    norm = R.Normalize(norm)
    if norm == "current value" or norm == "value now" then return true end
    if R.HasNormalizedPhrase(norm, "it")
        or R.HasNormalizedPhrase(norm, "that")
        or R.HasNormalizedPhrase(norm, "this")
    then
        return true
    end
    return R.ContainsAny(norm, {
        "last setting", "last option", "same setting", "same option",
        "the setting", "the option", "last change", "previous change",
    })
end

function R.LastChangeFollowupHasExplicitOtherSubject(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, {
        "result 1", "result 2", "result 3", "option 1", "option 2", "option 3",
        "choice 1", "choice 2", "choice 3",
    }) then
        return true
    end
    if norm:find(" of ", 1, true)
        and not R.ContainsAny(norm, { "of it", "of that", "of this", "of the last setting", "of last setting", "of the last option", "of last option" })
    then
        return true
    end
    if norm:find(" for ", 1, true)
        and not R.ContainsAny(norm, { "for it", "for that", "for this", "for the last setting", "for last setting", "for the last option", "for last option" })
    then
        return true
    end
    return false
end

function R.LastChangedSettingCurrentValueLine(item, ctx)
    local setting = item and item.setting
    if not setting then return nil end
    local value
    if type(setting.get) == "function" then
        value = setting.get()
    else
        value = ctx and ctx.lastValue
    end
    local valueLabel = R.RegistryValueLabel(setting, value)
    if valueLabel == nil or valueLabel == "" then return nil end
    return "Current value: " .. tostring(item.label or setting.label or "that setting") .. " is " .. tostring(valueLabel) .. "."
end

function R.TryLastChangeSettingFollowup(text)
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if not R.LastChangeFollowupHasSubject(norm) or R.LastChangeFollowupHasExplicitOtherSubject(norm) then return nil end

    local asksValue = R.ContainsAny(norm, R.LAST_CHANGE_VALUE_FOLLOWUP_TERMS)
    local asksLocation = R.ContainsAny(norm, R.LAST_CHANGE_LOCATION_FOLLOWUP_TERMS)
    local asksExplain = R.ContainsAny(norm, R.LAST_CHANGE_EXPLAIN_FOLLOWUP_TERMS)
    if not asksValue and not asksLocation and not asksExplain then return nil end

    local item, ctx = R.LastChangedSettingItem()
    if not item then return nil end

    local label = tostring(item.label or "Last changed setting")
    local pageLabel = tostring(item.pageLabel or "the matching MSUF page")
    local controlType = tostring(item.controlType or (item.setting and item.setting.type) or "setting")
    local valueLine = R.LastChangedSettingCurrentValueLine(item, ctx)
    local example = R.RegistrySettingExample(item)
    local lines = {}

    if asksLocation and not asksValue and not asksExplain then
        lines[#lines + 1] = label .. " setting location"
        lines[#lines + 1] = "This is the last setting I changed. It lives on " .. pageLabel .. " and is " .. R.RegistrySettingTypeText(controlType) .. ". I did not change it from this location question."
        if valueLine then lines[#lines + 1] = valueLine end
        if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; " .. example .. "." end
        lines[#lines + 1] = "You can ask: what does it do | what is it now | undo"
        return {
            text = table.concat(lines, "\n"),
            status = "info",
            result = "info",
            summary = "Shows where the last changed setting lives.",
        }
    end

    if asksValue and not asksExplain then
        lines[#lines + 1] = label .. " current value"
        lines[#lines + 1] = "This is the last setting I changed."
        lines[#lines + 1] = valueLine or "I do not have a saved current value for " .. label .. "."
        lines[#lines + 1] = "It lives on " .. pageLabel .. ". Ask 'undo' to revert the last Assistant change if needed."
        lines[#lines + 1] = "You can ask: where is it | what does it do" .. (example and (" | " .. example) or "")
        return {
            text = table.concat(lines, "\n"),
            status = "info",
            result = "info",
            summary = "Shows the current value for the last changed setting.",
        }
    end

    lines[#lines + 1] = label .. " explanation"
    lines[#lines + 1] = "This is the last setting I changed."
    lines[#lines + 1] = R.RegistrySettingPurpose(item)
    lines[#lines + 1] = label .. " lives on " .. pageLabel .. ". It is " .. R.RegistrySettingTypeText(controlType) .. ". I did not change it from this explanation question."
    if valueLine then lines[#lines + 1] = valueLine end
    local choicesLine = R.RegistryEnumChoicesLine(item)
    if choicesLine then lines[#lines + 1] = choicesLine end
    if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; " .. example .. "." end
    lines[#lines + 1] = "You can ask: where is it | what is it now | undo"
    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Explains the last changed setting.",
    }
end

function R.RegistryRelatedLine(close)
    if type(close) ~= "table" or #close <= 1 then return nil end
    local related = {}
    for i = 2, math.min(#close, 3) do
        local label = close[i] and close[i].item and close[i].item.label
        if label then related[#related + 1] = tostring(label) end
    end
    if #related == 0 then return nil end
    return "Related nearby settings: " .. table.concat(related, "; ") .. "."
end

function R.RegistrySubjectMatchesLabel(item, subject)
    local label = R.Normalize(item and item.label or "")
    subject = R.Normalize(subject)
    if label == "" or subject == "" then return false end
    local matched = 0
    for token in subject:gmatch("%S+") do
        if #token > 2 then
            if not R.HasNormalizedPhrase(label, token) then return false end
            matched = matched + 1
        end
    end
    return matched > 0
end

function R.RegistrySettingCurrentValueLine(item)
    local setting = item and item.setting
    if not setting or type(setting.get) ~= "function" then return nil end
    local value = setting.get()
    local valueLabel = R.RegistryValueLabel(setting, value)
    if valueLabel == nil or valueLabel == "" then return nil end
    local label = tostring(item.label or setting.label or "MSUF setting")
    return "Current value: " .. label .. " is " .. tostring(valueLabel) .. "."
end

function R.RegistrySettingItemForKey(settingKey)
    settingKey = tostring(settingKey or "")
    if settingKey == "" then return nil end
    local registry = A.Registry
    local setting = registry and type(registry.GetSetting) == "function" and registry:GetSetting(settingKey) or nil
    if not setting then return nil end
    local page = setting.page or R.FallbackPageForSetting(setting)
    local pageLabel = page and A.DisplayPageLabel and A.DisplayPageLabel(page, "MSUF page") or nil
    local label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or tostring(setting.label or settingKey)
    return {
        kind = "setting",
        key = settingKey,
        settingKey = settingKey,
        label = label,
        page = page,
        pageLabel = pageLabel,
        category = setting.category,
        controlType = setting.type,
        setting = setting,
        canOpen = page ~= nil,
        canExplain = true,
    }
end

function R.RegistryVisibilityCurrentValueSettingKey(subject, norm)
    subject = R.Normalize(subject)
    norm = R.Normalize(norm)
    if subject == "" then return nil end
    if not R.ContainsAny(norm, {
        "visible", "visble", "shown", "showing", "hidden", "hiden",
        "enabled", "enabld", "disabled", "disabld",
        "turned on", "turnd on", "turned off", "turnd off",
        "on", "off", "show", "shows", "shwo", "shwos", "see", "se",
    }) then return nil end

    if R.ContainsAny(subject, { "party frame", "party frames", "party group frame", "party group frames" }) then return "gf_party.enabled" end
    if R.ContainsAny(subject, { "raid frame", "raid frames", "raid group frame", "raid group frames" }) then return "gf_raid.enabled" end
    if R.ContainsAny(subject, { "mythic raid frame", "mythic raid frames", "mythic frame", "mythic frames", "mythic group frame", "mythic group frames" }) then return "gf_mythicraid.enabled" end

    if R.ContainsAny(subject, { "player frame", "my frame", "self frame" }) then return "player.enabled" end
    if R.ContainsAny(subject, { "target frame", "target unit frame" }) then return "target.enabled" end
    if R.ContainsAny(subject, { "focus frame", "focus unit frame" }) then return "focus.enabled" end
    if R.ContainsAny(subject, { "pet frame", "pet unit frame" }) then return "pet.enabled" end
    if R.ContainsAny(subject, { "boss frame", "boss frames", "boss unit frame", "boss unit frames" }) then return "boss.enabled" end
    if R.ContainsAny(subject, { "target of target frame", "target of target unit frame", "targettarget frame", "tot frame" }) then return "targettarget.enabled" end
    if R.ContainsAny(subject, { "focus target frame", "focus target unit frame", "focustarget frame" }) then return "focustarget.enabled" end
    return nil
end

function R.RegistryCurrentValueClarification(subject, entries, limit)
    local lines = { "Current value clarification" }
    local visible = math.min(tonumber(limit) or 3, #(entries or {}))
    if visible > 0 then
        lines[#lines + 1] = "I found multiple possible MSUF settings for " .. tostring(subject or "that request") .. ":"
        for i = 1, visible do
            local item = entries[i] and entries[i].item or {}
            local line = R.RegistryLocationLine(i, item)
            local valueLine = R.RegistrySettingCurrentValueLine(item)
            if valueLine then
                line = line .. "; " .. valueLine
            end
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = "Pick a result or ask for the exact setting name. I did not change anything."
        lines[#lines + 1] = "You can ask: current value of result 1 | explain result 1 | open result 1"
        return {
            text = table.concat(lines, "\n"),
            status = "info",
            result = "info",
            summary = "Assistant registry current value clarification",
            searchResults = R.RegistryLocationResultFollowups(entries, visible),
        }
    end

    lines[#lines + 1] = "I could not confidently identify which MSUF setting you mean. Name the frame and setting, for example 'current value of target cast bar height'."
    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant registry current value clarification",
    }
end

R.CROSS_FRAME_TEXT_UNIT_TERMS = {
    { unit = "targettarget", label = "Target of Target", terms = { "target of target", "targettarget", "targets target", "tot" } },
    { unit = "focustarget", label = "Focus Target", terms = { "focus target", "focustarget" } },
    { unit = "player", label = "Player", terms = { "player", "player frame", "my frame", "self" } },
    { unit = "target", label = "Target", terms = { "target", "target frame" } },
    { unit = "focus", label = "Focus", terms = { "focus", "focus frame" } },
    { unit = "pet", label = "Pet", terms = { "pet", "pet frame" } },
    { unit = "boss", label = "Boss", terms = { "boss", "boss frame", "boss frames" } },
}

function R.CrossFrameTextUnitInFragment(fragment)
    fragment = R.Normalize(fragment)
    if fragment == "" then return nil, nil end
    for i = 1, #R.CROSS_FRAME_TEXT_UNIT_TERMS do
        local spec = R.CROSS_FRAME_TEXT_UNIT_TERMS[i]
        for j = 1, #(spec.terms or {}) do
            if R.HasNormalizedPhrase(fragment, spec.terms[j]) then return spec.unit, spec.label end
        end
    end
    return nil, nil
end

function R.CrossFrameTextRequestParts(norm)
    norm = R.Normalize(norm)
    if norm == "" then return nil end
    if not R.ContainsAny(norm, {
        "name", "name text", "health text", "hp text", "power text", "mana text",
        "font size", "text size", "bigger", "larger", "smaller",
    }) then
        return nil
    end
    local patterns = {
        "^(.-)%s+on%s+the%s+(.+)$",
        "^(.-)%s+on%s+(.+)$",
        "^(.-)%s+from%s+the%s+(.+)$",
        "^(.-)%s+from%s+(.+)$",
        "^(.-)%s+in%s+the%s+(.+)$",
        "^(.-)%s+in%s+(.+)$",
    }
    for i = 1, #patterns do
        local before, after = norm:match(patterns[i])
        local subjectUnit, subjectLabel = R.CrossFrameTextUnitInFragment(before)
        local frameUnit, frameLabel = R.CrossFrameTextUnitInFragment(after)
        if subjectUnit and frameUnit then
            return subjectUnit, subjectLabel, frameUnit, frameLabel
        end
    end
    return nil
end

function R.CrossFrameTextFieldLabel(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, { "health text", "hp text", "health value", "hp value" }) then return "health text" end
    if R.ContainsAny(norm, { "power text", "mana text", "resource text" }) then return "power text" end
    if R.ContainsAny(norm, { "font size", "text size", "bigger", "larger", "smaller" }) then return "name text size" end
    if R.ContainsAny(norm, { "name", "name text" }) then return "name text" end
    return "text"
end

function R.CrossFrameVisualFieldLabel(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, { "castbar", "cast bar", "cast bars" }) then return "cast bar" end
    if R.ContainsAny(norm, { "debuff", "debuffs", "debuff icons", "debuff lane" }) then return "debuffs" end
    if R.ContainsAny(norm, { "buff", "buffs", "buff icons", "buff lane" }) then return "buffs" end
    if R.ContainsAny(norm, { "aura", "auras", "aura icons" }) then return "auras" end
    if R.ContainsAny(norm, {
        "raid marker", "raid markers", "raid icon", "raid icons", "marker icon",
        "moon icon", "skull icon", "cross icon", "square icon", "triangle icon",
        "diamond icon", "star icon", "circle icon",
    }) then return "raid marker icon" end
    if R.ContainsAny(norm, { "portrait", "portraits" }) then return "portrait" end
    if R.ContainsAny(norm, { "health bar", "hp bar" }) then return "health bar" end
    if R.ContainsAny(norm, { "power bar", "mana bar", "resource bar" }) then return "power bar" end
    return nil
end

function R.CrossFrameVisualRequestParts(norm)
    norm = R.Normalize(norm)
    if norm == "" then return nil end
    if not R.CrossFrameVisualFieldLabel(norm) then return nil end

    local patterns = {
        "^(.-)%s+on%s+the%s+(.+)$",
        "^(.-)%s+on%s+(.+)$",
        "^(.-)%s+in%s+the%s+(.+)$",
        "^(.-)%s+in%s+(.+)$",
        "^(.-)%s+inside%s+the%s+(.+)$",
        "^(.-)%s+inside%s+(.+)$",
        "^(.-)%s+from%s+the%s+(.+)$",
        "^(.-)%s+from%s+(.+)$",
    }
    for i = 1, #patterns do
        local before, after = norm:match(patterns[i])
        local fieldLabel = before and R.CrossFrameVisualFieldLabel(before) or nil
        local subjectUnit, subjectLabel = R.CrossFrameTextUnitInFragment(before)
        local frameUnit, frameLabel = R.CrossFrameTextUnitInFragment(after)
        if fieldLabel and subjectUnit and frameUnit then
            return subjectUnit, subjectLabel, frameUnit, frameLabel, fieldLabel
        end
    end
    return nil
end

function A.RouterTryCrossFrameTextRequestShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    local subjectUnit, subjectLabel, frameUnit, frameLabel = R.CrossFrameTextRequestParts(norm)
    if not subjectUnit or not frameUnit or subjectUnit == frameUnit then return nil end

    local fieldLabel = R.CrossFrameTextFieldLabel(norm)
    local isTotInlineName = subjectUnit == "targettarget"
        and frameUnit == "target"
        and fieldLabel == "name text"
        and not R.ContainsAny(norm, { "health", "hp", "power", "mana", "font size", "text size", "bigger", "larger", "smaller" })
    if isTotInlineName then return nil end

    local body
    local examples
    local actions
    if subjectUnit == "targettarget" and frameUnit == "target" then
        body = "Target of Target name can be shown inline on the Target frame, but only as the inline Target Target text option. MSUF does not expose separate inline Target of Target health, power, or font-size controls on the Target frame. I did not change anything from this cross-frame request."
        examples = "show target of target name on target frame; open target; open target of target; make target of target name bigger on target of target frame."
        actions = "Open Target | Open Target of Target | show target of target name on target frame"
    elseif subjectUnit == "focustarget" and frameUnit == "focus" then
        body = "Focus Target has its own frame and text options. MSUF does not expose separate inline Focus Target text on the Focus frame. I did not change anything from this cross-frame request."
        examples = "show focus target frame; show focus target name; open focus target."
        actions = "Open Focus Target | show focus target name"
    else
        body = subjectLabel .. " " .. fieldLabel .. " belongs to the " .. subjectLabel .. " frame, while " .. frameLabel .. " text belongs to the " .. frameLabel .. " frame. I did not change both frames from this cross-frame request."
        local subjectCommand = "show " .. subjectLabel:lower() .. " name"
        if fieldLabel == "health text" then
            subjectCommand = "show " .. subjectLabel:lower() .. " health text"
        elseif fieldLabel == "power text" then
            subjectCommand = "show " .. subjectLabel:lower() .. " power text"
        elseif fieldLabel == "name text size" then
            subjectCommand = "make " .. subjectLabel:lower() .. " name bigger"
        end
        examples = subjectCommand .. "; open " .. subjectLabel:lower() .. "; open " .. frameLabel:lower() .. "."
        actions = "Open " .. subjectLabel .. " | Open " .. frameLabel
    end

    return {
        text = "Cross-frame text clarification\n" .. body .. "\nExamples: " .. examples .. "\nYou can ask: " .. actions,
        status = "info",
        result = "info",
        summary = "Assistant cross-frame text clarification",
    }
end

function A.RouterTryCrossFrameVisualRequestShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    local subjectUnit, subjectLabel, frameUnit, frameLabel, fieldLabel = R.CrossFrameVisualRequestParts(norm)
    if not subjectUnit or not frameUnit or subjectUnit == frameUnit or not fieldLabel then return nil end

    local examples
    local actions
    if fieldLabel == "cast bar" then
        examples = "show " .. subjectLabel:lower() .. " cast bar; open cast bars; open " .. subjectLabel:lower() .. "."
        actions = "Open Cast Bars | Open " .. subjectLabel .. " | Open " .. frameLabel
    elseif fieldLabel == "buffs" or fieldLabel == "debuffs" or fieldLabel == "auras" then
        examples = "show " .. subjectLabel:lower() .. " " .. fieldLabel .. "; show " .. frameLabel:lower() .. " " .. fieldLabel .. "; open auras."
        actions = "Open Auras | Open " .. subjectLabel .. " | Open " .. frameLabel
    else
        examples = "show " .. subjectLabel:lower() .. " " .. fieldLabel .. "; show " .. frameLabel:lower() .. " " .. fieldLabel .. "; open " .. subjectLabel:lower() .. "."
        actions = "Open " .. subjectLabel .. " | Open " .. frameLabel
    end

    local plural = fieldLabel == "buffs" or fieldLabel == "debuffs" or fieldLabel == "auras"
    local be = plural and "are" or "is"
    local belongs = plural and "They belong" or "It belongs"
    local settingNoun = plural and "settings" or "setting"
    local body = subjectLabel .. " " .. fieldLabel .. " " .. be .. " frame-specific. " .. belongs .. " to the " .. subjectLabel .. " frame; the " .. frameLabel .. " frame has its own separate " .. fieldLabel .. " " .. settingNoun .. " when MSUF exposes one. I did not change either frame from this cross-frame request."
    return {
        text = "Cross-frame visual clarification\n" .. body .. "\nExamples: " .. examples .. "\nYou can ask: " .. actions,
        status = "info",
        result = "info",
        summary = "Assistant cross-frame visual clarification",
    }
end

function R.IsTargetTargetInlineLocationQuestion(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    return norm:match("^where%s+") ~= nil
        or norm:match("^which%s+") ~= nil
        or norm:match("^what%s+setting") ~= nil
        or norm:match("^what%s+option") ~= nil
        or norm:match("^what%s+controls") ~= nil
        or norm:match("^how%s+do%s+i") ~= nil
        or norm:match("^how%s+can%s+i") ~= nil
        or norm:match("^can%s+i") ~= nil
        or norm:match("^is%s+there%s+a%s+way") ~= nil
        or R.ContainsAny(norm, { "help me find", "help me locate", "tell me where", "show me where", "looking for" })
end

function A.RouterTryTargetTargetInlineNameShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeTargetTargetInlineNameRequest(norm) then return nil end
    if norm:match("^why%s+") then return nil end

    if R.IsTargetTargetInlineLocationQuestion(norm) then
        if A.RouterTryRegistrySettingLocationShortcut then
            return A.RouterTryRegistrySettingLocationShortcut("where can I turn on Target Target Inline Text", coreHandler)
        end
        return {
            text = "Target Target Inline Text setting location\nTarget Target Inline Text lives on Target. I did not change it.",
            status = "info",
            result = "info",
            summary = "Assistant ToT inline location",
        }
    end

    local wantsOff = R.WantsVisibilityOff(norm)
    local wantsOn = R.WantsVisibilityOn(norm) or R.ContainsAny(norm, { "visible" })
    if not wantsOff and not wantsOn then return nil end

    local command = (wantsOff and "turn off " or "turn on ") .. "Target Target Inline Text"
    return R.CoreControl(coreHandler, command, "Target Target Inline Text lives on Target. Ask 'open target' to inspect it first.", "info")
end

function R.DependentTargetProblemKind(norm)
    norm = R.Normalize(norm)
    if R.ContainsAny(norm, { "target of target", "targettarget", "targets target", "tot" }) then
        return "targettarget", "Target of Target", "Target", "Target Target Inline Text", "Target of Target Name"
    end
    if R.ContainsAny(norm, { "focus target", "focustarget" }) then
        return "focustarget", "Focus Target", "Focus", nil, "Focus Target Name"
    end
    return nil
end

function R.LooksLikeDependentTargetProblem(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    if R.ContainsAny(norm, { "castbar", "cast bar", "cast bars", "buff", "buffs", "debuff", "debuffs", "aura", "auras" }) then return false end
    if not R.DependentTargetProblemKind(norm) then return false end
    if R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS) then return true end
    return norm:match("^why%s+") ~= nil
        or R.ContainsAny(norm, { "where is", "where are", "where can", "how do i show", "how can i show" })
end

function R.DependentTargetMentionsParentFrame(norm, parentLabel)
    norm = R.Normalize(norm)
    parentLabel = R.Normalize(parentLabel)
    if parentLabel == "target" then
        return R.ContainsAny(norm, { "target frame", "on target", "on the target", "in target", "in the target", "inside target", "inside the target" })
    end
    if parentLabel == "focus" then
        return R.ContainsAny(norm, { "focus frame", "on focus", "on the focus", "in focus", "in the focus", "inside focus", "inside the focus" })
    end
    return false
end

function A.RouterTryDependentTargetTroubleshootingShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeDependentTargetProblem(norm) then return nil end

    local unit, unitLabel, parentLabel, inlineLabel, frameNameLabel = R.DependentTargetProblemKind(norm)
    if not unit or not unitLabel or not parentLabel then return nil end

    local mentionsParentFrame = R.DependentTargetMentionsParentFrame(norm, parentLabel)
    local followQuery = frameNameLabel
    local exactLabel = frameNameLabel
    local body
    local examples
    local actions

    if unit == "targettarget" and mentionsParentFrame and inlineLabel then
        followQuery = inlineLabel
        exactLabel = inlineLabel
        body = "On the Target frame, Target of Target is shown through Target Target Inline Text. If it is missing, check that setting first. It only has visible content when your current target actually has a target. The separate Target of Target frame also has its own visibility and name settings. I did not change anything from this troubleshooting question."
        examples = "turn on target target inline text; open target; open target of target; show target of target frame."
        actions = "Open Target | Open Target of Target | Current Value"
    elseif unit == "focustarget" and mentionsParentFrame then
        body = "Focus Target is a separate MSUF frame, not inline text inside the Focus frame. If it is missing, check Focus Target frame visibility, Focus Target Name, frame alpha/size, and whether your focus actually has a target. I did not change anything from this troubleshooting question."
        examples = "show focus target frame; show focus target name; open focus target."
        actions = "Open Focus Target | Current Value"
    else
        body = unitLabel .. " only has visible content when the watched unit has a target. If it is missing, check " .. unitLabel .. " frame visibility, " .. frameNameLabel .. ", frame alpha/size, active profile, and whether the unit actually has a target. I did not change anything from this troubleshooting question."
        examples = "show " .. unitLabel:lower() .. " frame; show " .. unitLabel:lower() .. " name; open " .. unitLabel:lower() .. "."
        actions = "Open " .. unitLabel .. " | Current Value"
    end

    return {
        text = unitLabel .. " visibility help\n" .. body .. "\nExamples: " .. examples .. "\nYou can ask: " .. actions,
        status = "info",
        result = "info",
        summary = "Assistant dependent target troubleshooting",
        searchResults = R.SettingFollowupResultsByQuery(followQuery, exactLabel),
    }
end

function A.RouterTryRegistrySettingExplainShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeRegistrySettingExplainQuestion(norm) then return nil end
    local subject = R.RegistryExplainSubject(norm)
    local entries = R.RegistrySettingSearchEntries(subject ~= "" and subject or text, norm, 16)
    if not entries or #entries == 0 then return nil end

    local top = entries[1]
    local exactLabelMatch = R.RegistrySubjectMatchesLabel(top and top.item, subject)
    if not top or (top.score < 340 and not (exactLabelMatch and top.score >= 260)) then return nil end
    if (tonumber(top.rawScore) or 0) < 260 and not R.RegistryRequestedScope(norm) then return nil end

    local close = { top }
    for i = 2, #entries do
        if #close >= 3 then break end
        local includeRelated = entries[i].score >= top.score - 140
            and (tonumber(entries[i].rawScore) or 0) >= (tonumber(top.rawScore) or 0) - 120
            and R.RegistryCloseMatchAllowed(entries[i].item, norm)
        if not includeRelated and exactLabelMatch
            and R.RegistrySubjectMatchesLabel(entries[i].item, subject)
            and R.RegistryCloseMatchAllowed(entries[i].item, norm)
        then
            includeRelated = true
        end
        if includeRelated then
            close[#close + 1] = entries[i]
        end
    end

    local item = top.item or {}
    local label = tostring(item.label or "MSUF setting")
    local pageLabel = tostring(item.pageLabel or "MSUF page")
    local controlType = tostring(item.controlType or (item.setting and item.setting.type) or "setting")
    local example = R.RegistrySettingExample(item)
    local lines = {
        label .. " explanation",
        R.RegistrySettingPurpose(item),
        label .. " lives on " .. pageLabel .. ". It is " .. R.RegistrySettingTypeText(controlType) .. ". I did not change it.",
    }
    local valueLine = R.RegistryCurrentValueLine(item)
    if valueLine then lines[#lines + 1] = valueLine end
    local choicesLine = R.RegistryEnumChoicesLine(item)
    if choicesLine then lines[#lines + 1] = choicesLine end
    local relatedLine = R.RegistryRelatedLine(close)
    if relatedLine then lines[#lines + 1] = relatedLine end
    if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; " .. example .. "." end
    lines[#lines + 1] = "You can ask: Open " .. pageLabel .. " | Current Value" .. (example and (" | " .. example) or "")

    return {
        text = table.concat(lines, "\n"),
        status = "applied",
        result = "applied",
        summary = "Assistant registry setting explanation",
        searchResults = R.RegistryLocationResultFollowups(close, #close),
    }
end

function A.RouterTryRegistrySettingCurrentValueShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeRegistrySettingCurrentValueQuestion(norm) then return nil end
    local subject = R.RegistryCurrentValueSubject(norm)
    local directKey = R.RegistryVisibilityCurrentValueSettingKey(subject, norm)
    local directItem = directKey and R.RegistrySettingItemForKey(directKey) or nil
    local entries = directItem and { { item = directItem, score = 9999, rawScore = 9999 } }
        or R.RegistrySettingSearchEntries(subject ~= "" and subject or text, norm, 16)
    if not entries or #entries == 0 then return R.RegistryCurrentValueClarification(subject, nil, 0) end
    local top = entries[1]
    if not directItem and (not top or (tonumber(top.rawScore) or 0) < 220) then
        return R.RegistryCurrentValueClarification(subject, nil, 0)
    end
    if not directItem and R.RegistryCurrentValueSubjectTooBroad(subject) then
        return R.RegistryCurrentValueClarification(subject, entries, 3)
    end

    local exactLabelMatch = directItem ~= nil or R.RegistrySubjectMatchesLabel(top and top.item, subject)
    if not top or (top.score < 340 and not (exactLabelMatch and top.score >= 260)) then
        return R.RegistryCurrentValueClarification(subject, entries, 3)
    end
    if (tonumber(top.rawScore) or 0) < 260 and not R.RegistryRequestedScope(norm) then
        return R.RegistryCurrentValueClarification(subject, entries, 3)
    end

    local close = { top }
    for i = 2, #entries do
        if #close >= 3 then break end
        local includeRelated = entries[i].score >= top.score - 140
            and (tonumber(entries[i].rawScore) or 0) >= (tonumber(top.rawScore) or 0) - 120
            and R.RegistryCloseMatchAllowed(entries[i].item, norm)
        if not includeRelated and exactLabelMatch
            and R.RegistrySubjectMatchesLabel(entries[i].item, subject)
            and R.RegistryCloseMatchAllowed(entries[i].item, norm)
        then
            includeRelated = true
        end
        if includeRelated then close[#close + 1] = entries[i] end
    end
    if #close > 1 and not exactLabelMatch then
        return R.RegistryCurrentValueClarification(subject, close, #close)
    end

    local item = top.item or {}
    local setting = item.setting
    local label = tostring(item.label or "MSUF setting")
    local pageLabel = tostring(item.pageLabel or "MSUF page")
    local controlType = tostring(item.controlType or (setting and setting.type) or "setting")
    local valueLine = R.RegistrySettingCurrentValueLine(item)
    local example = R.RegistrySettingExample(item)
    local lines = { label .. " current value" }

    local expectedBoolean = R.RegistryCurrentValueExpectedBoolean(norm)
    if setting and setting.type == "boolean" and expectedBoolean ~= nil and type(setting.get) == "function" then
        local current = setting.get()
        if type(current) == "boolean" then
            lines[#lines + 1] = (current == expectedBoolean and "Yes." or "No.")
        end
    end

    lines[#lines + 1] = valueLine or ("I cannot read a saved current value for " .. label .. " right now.")
    lines[#lines + 1] = label .. " lives on " .. pageLabel .. ". It is " .. R.RegistrySettingTypeText(controlType) .. ". I did not change it."
    local choicesLine = R.RegistryEnumChoicesLine(item)
    if choicesLine then lines[#lines + 1] = choicesLine end
    local relatedLine = R.RegistryRelatedLine(close)
    if relatedLine then lines[#lines + 1] = relatedLine end
    if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; " .. example .. "." end
    lines[#lines + 1] = "You can ask: Open " .. pageLabel .. " | Explain Result 1" .. (example and (" | " .. example) or "")

    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant registry setting current value",
        searchResults = R.RegistryLocationResultFollowups({ top }, 1),
    }
end

function A.RouterTryRegistrySettingDecisionShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeRegistrySettingDecisionQuestion(norm) then return nil end
    local subject = R.RegistryDecisionSubject(norm)
    local entries = R.RegistrySettingSearchEntries(subject ~= "" and subject or text, norm, 16)
    if not entries or #entries == 0 then return nil end

    local top = entries[1]
    local exactLabelMatch = R.RegistrySubjectMatchesLabel(top and top.item, subject)
    if not top or (top.score < 340 and not (exactLabelMatch and top.score >= 260)) then return nil end
    if (tonumber(top.rawScore) or 0) < 260 and not R.RegistryRequestedScope(norm) then return nil end

    local item = top.item or {}
    local label = tostring(item.label or "MSUF setting")
    local pageLabel = tostring(item.pageLabel or "MSUF page")
    local example = R.RegistrySettingExample(item)
    local lines = {
        label .. " decision help",
        R.RegistrySettingPurpose(item),
        label .. " lives on " .. pageLabel .. ". I did not change it.",
    }
    local valueLine = R.RegistryCurrentValueLine(item)
    if valueLine then lines[#lines + 1] = valueLine end
    if R.ContainsAny(norm, { "is it safe", "would it be safe" }) then
        lines[#lines + 1] = "Normal MSUF setting changes can be undone, but the safer first step is to inspect the setting or ask for its current value before changing it."
    else
        lines[#lines + 1] = "Keep it enabled if it improves readability or gameplay information for you. Turn it off only if it is visual noise, duplicated elsewhere, or part of a layout you intentionally simplified."
    end
    if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; " .. example .. "." end
    lines[#lines + 1] = "You can ask: Open " .. pageLabel .. " | Current Value" .. (example and (" | " .. example) or "")

    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant registry setting decision guidance",
        searchResults = R.RegistryLocationResultFollowups({ top }, 1),
    }
end

function A.RouterTryRegistrySettingTroubleshootingShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeRegistrySettingTroubleshootingQuestion(norm) then return nil end
    local subject = R.RegistryTroubleshootingSubject(norm)
    local entries = R.RegistrySettingSearchEntries(subject ~= "" and subject or text, norm, 16)
    if not entries or #entries == 0 then return nil end

    local top = entries[1]
    local exactLabelMatch = R.RegistrySubjectMatchesLabel(top and top.item, subject)
    if not top or (top.score < 340 and not (exactLabelMatch and top.score >= 260)) then return nil end
    if (tonumber(top.rawScore) or 0) < 260 and not R.RegistryRequestedScope(norm) then return nil end

    local item = top.item or {}
    local label = tostring(item.label or "MSUF setting")
    local pageLabel = tostring(item.pageLabel or "MSUF page")
    local example = R.RegistrySettingExample(item)
    local lines = {
        label .. " troubleshooting help",
        R.RegistrySettingPurpose(item),
        label .. " lives on " .. pageLabel .. ". I did not change it.",
    }
    local valueLine = R.RegistryCurrentValueLine(item)
    if valueLine then lines[#lines + 1] = valueLine end
    lines[#lines + 1] = "If it is missing or not showing, check this setting first, then the related parent visibility option, size/count limits, alpha/opacity, filters, combat state, and the active profile."
    if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; current value; " .. example .. "." end
    lines[#lines + 1] = "You can ask: Open " .. pageLabel .. " | Current Value" .. (example and (" | " .. example) or "")

    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant registry setting troubleshooting",
        searchResults = R.RegistryLocationResultFollowups({ top }, 1),
    }
end

function A.RouterTryRegistrySettingLocationShortcut(text, coreHandler)
    local norm = R.Normalize(text)
    if not R.LooksLikeRegistrySettingLocationQuestion(norm) then return nil end
    local subject = R.RegistryLocationSubject(norm)
    local entries = R.RegistrySettingSearchEntries(subject ~= "" and subject or text, norm, 16)
    if not entries or #entries == 0 then return nil end

    local top = entries[1]
    if not top or top.score < 340 then return nil end
    local item = top.item or {}
    local label = tostring(item.label or "MSUF setting")
    local pageLabel = tostring(item.pageLabel or "MSUF page")
    local controlType = tostring(item.controlType or "setting")
    local example = R.RegistrySettingExample(item)
    local close = {}
    close[1] = top
    for i = 2, #entries do
        if #close >= 3 then break end
        if entries[i].score >= top.score - 140
            and (tonumber(entries[i].rawScore) or 0) >= (tonumber(top.rawScore) or 0) - 120
            and R.RegistryCloseMatchAllowed(entries[i].item, norm)
        then
            close[#close + 1] = entries[i]
        end
    end

    local lines
    if #close > 1 then
        lines = { "Matching settings location" }
        lines[#lines + 1] = "Closest MSUF settings:"
        for i = 1, #close do lines[#lines + 1] = R.RegistryLocationLine(i, close[i].item) end
        lines[#lines + 1] = "I did not change anything from this location question. Ask to open or explain a result before changing it."
    else
        lines = {
            label .. " setting location",
            label .. " lives on " .. pageLabel .. ". It is " .. R.RegistrySettingTypeText(controlType) .. ". I did not change it from this location question.",
        }
    end
    if example and example ~= "" then lines[#lines + 1] = "Examples: open " .. pageLabel:lower() .. "; " .. example .. "." end
    lines[#lines + 1] = "You can ask: Open " .. pageLabel .. " | Explain Result 1" .. (example and (" | " .. example) or "")

    return {
        text = table.concat(lines, "\n"),
        status = "applied",
        result = "applied",
        summary = "Assistant registry setting location",
        searchResults = R.RegistryLocationResultFollowups(close, #close),
    }
end

function R.TryGeneralGuidanceShortcut(text, coreHandler)    local norm = R.Normalize(text)
    if norm == "" then return nil end

    local combinedGuidanceResult = R.CombinedGuidanceReply(norm)
    if combinedGuidanceResult then return combinedGuidanceResult end

    local classGuidanceResult = R.ClassGuidanceReply(norm)
    if classGuidanceResult then return classGuidanceResult end

    if R.LooksLikeRoleGuidanceRequest(norm) then
        return R.RoleGuidanceReply(norm)
    end

    if R.LooksLikeContentGuidanceRequest(norm) then
        return R.ContentGuidanceReply(norm)
    end

    if R.ContainsAny(norm, R.SETUP_GUIDANCE_TERMS) then
        if type(coreHandler) == "function" then
            local result = coreHandler("guided setup")
            if result and not A.RouterIsUnknownResult(result) then return result end
        end
        return R.SetupGuidanceReply()
    end

    if R.ContainsAny(norm, R.RECOVERY_GUIDANCE_TERMS) then
        return R.RecoveryGuidanceReply()
    end

    if R.ContainsAny(norm, R.CONTEXTLESS_GUIDANCE_TERMS) then
        return R.ContextlessGuidanceReply()
    end

    return nil
end

R.GROUP_AURA_CONTEXT_BLOCKERS = {    "unitframe", "unitframes", "unit frame", "unit frames",
    "target of target", "focus target", "player", "target", "focus", "pet", "boss",
    "party", "raid", "mythic raid", "party frames", "raid frames",
    "castbar", "cast bar", "profile", "profiles", "class resource", "class power", "gameplay",
    "edit mode", "editmode", "bearbeitungsmodus",
}

function R.ShouldKeepGroupAuraContext(norm)    return M and M.activeKey == "gf_auras"
        and R.ContainsAny(norm, R.AURA_BUFF_TERMS)
        and not R.ContainsAny(norm, R.GROUP_AURA_CONTEXT_BLOCKERS)
end

function R.ShouldSkipContext(text)    local norm = R.Normalize(text)
    if norm == "" then return true end
    if R.ContainsAny(norm, R.FLOW_TERMS) then return true end
    if R.ContainsAny(norm, R.NAV_HELP_TERMS) then return true end
    if R.ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then return true end
    if R.ContainsAny(norm, R.EXPLICIT_DOMAIN_TERMS) and not R.ShouldKeepGroupAuraContext(norm) then return true end
    if R.ContainsAny(norm, {
        "it", "that", "this", "same", "do it", "do that", "again", "more", "less",
        "opposite", "other way", "hide it", "clear it", "remove it", "move it",
    }) then return true end
    if R.ContainsAny(norm, {
        "unitframe", "unitframes", "unit frame", "unit frames",
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    }) then return true end
    local parser = A.Parser or {}
    if type(parser.DetectUnits) == "function" and #(parser.DetectUnits(norm) or {}) > 0 then return true end
    if type(parser.DetectGroups) == "function" and #(parser.DetectGroups(norm) or {}) > 0 then return true end
    return false
end

function R.CurrentPageContext()    local key = M and M.activeKey
    if type(key) ~= "string" or key == "" then return nil end
    return R.PAGE_CONTEXT[key]
end

function R.CurrentPageSummaryLabel()    local ctx = R.CurrentPageContext()
    if ctx and type(ctx.label) == "string" and ctx.label ~= "" then return ctx.label end
    local key = M and M.activeKey
    if A and type(A.DisplayPageLabel) == "function" and type(key) == "string" and key ~= "" then
        return A.DisplayPageLabel(key, "MSUF page")
    end
    return "MSUF page"
end

function R.CurrentGroupScopePrefix()    local scope = M and M.gfScope
    if type(scope) ~= "string" or scope == "" then return nil end
    scope = R.Normalize(scope)
    return R.GROUP_SCOPE_PREFIXES[scope]
end

function R.AddUnique(out, value)    value = R.Trim(value)
    if value == "" then return end
    for i = 1, #out do if out[i] == value then return end end
    out[#out + 1] = value
end

function R.ContextPrefixes(ctx)    local prefixes = {}
    local key = M and M.activeKey
    if R.GROUP_CONTEXT_PAGES[key] then
        R.AddUnique(prefixes, R.CurrentGroupScopePrefix() or "")
    end
    if ctx and ctx.prefix then R.AddUnique(prefixes, ctx.prefix) end
    return prefixes
end

function R.StripBooleanWords(text)    local out = R.Normalize(text)
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
    return R.Trim(out)
end


function R.StripLeadingCommand(text)    local out = R.Normalize(text)
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
    return R.Trim(out)
end

function R.LeadingRelativeCommand(text)    local norm = R.Normalize(text)
    if R.ContainsAny(norm, { "decrease", "lower", "reduce", "smaller", "shrink", "less", "senke", "reduziere", "kleiner", "weniger" }) then
        return "decrease"
    end
    if R.ContainsAny(norm, { "increase", "raise", "higher", "more", "larger", "bigger", "grow", "erhoehe", "erhoehen", "hoeher", "groesser" }) then
        return "increase"
    end
    return nil
end

function R.AddBooleanContextVariants(variants, prefix, text)    local norm = R.Normalize(text)
    local noun = R.StripBooleanWords(text)
    if noun == "" then return end
    if R.ContainsAny(norm, { "off", "disable", "disabled", "hide", "aus", "deaktivieren", "ausschalten", "verstecken", "ausblenden" }) then
        R.AddUnique(variants, "turn off " .. prefix .. " " .. noun)
        R.AddUnique(variants, "disable " .. prefix .. " " .. noun)
    elseif R.ContainsAny(norm, { "on", "enable", "enabled", "show", "an", "aktivieren", "einschalten", "anzeigen", "einblenden" }) then
        R.AddUnique(variants, "turn on " .. prefix .. " " .. noun)
        R.AddUnique(variants, "enable " .. prefix .. " " .. noun)
    end
end

function R.ContextualVariants(text)    if R.ShouldSkipContext(text) then return nil end
    local ctx = R.CurrentPageContext()
    if not ctx or not ctx.prefix then return nil end
    local norm = R.Normalize(text)
    local variants = {}
    local prefixes = R.ContextPrefixes(ctx)
    local prefix = prefixes[1] or ctx.prefix

    if M.activeKey == "profiles" then
        if norm == "export" or norm == "export profile" then
            R.AddUnique(variants, "export current profile")
        elseif norm == "import" or norm == "import profile" then
            R.AddUnique(variants, "import profile")
        elseif norm == "copy" or norm == "copy profile" then
            R.AddUnique(variants, "copy current profile")
        else
            R.AddUnique(variants, prefix .. " " .. text)
        end
    elseif M.activeKey == "opt_castbar" then
        local noun = R.StripLeadingCommand(text)
        local relativeVerb = R.LeadingRelativeCommand(text)
        R.AddBooleanContextVariants(variants, "castbar", text)
        R.AddUnique(variants, "castbar " .. text)
        R.AddUnique(variants, "set castbar " .. text)
        if noun ~= "" and noun ~= R.Normalize(text) then
            if relativeVerb then R.AddUnique(variants, relativeVerb .. " castbar " .. noun) end
            R.AddUnique(variants, "set castbar " .. noun)
            R.AddUnique(variants, "change castbar " .. noun)
        end
        R.AddUnique(variants, "target castbar " .. text)
    elseif M.activeKey == "opt_bars" then
        local noun = R.StripLeadingCommand(text)
        local relativeVerb = R.LeadingRelativeCommand(text)
        R.AddBooleanContextVariants(variants, "bar", text)
        R.AddUnique(variants, "bar " .. text)
        R.AddUnique(variants, "set bar " .. text)
        if noun ~= "" and noun ~= R.Normalize(text) then
            if relativeVerb then R.AddUnique(variants, relativeVerb .. " bar " .. noun) end
            R.AddUnique(variants, "set bar " .. noun)
            R.AddUnique(variants, "change bar " .. noun)
        end
    elseif M.activeKey == "opt_fonts" then
        local noun = R.StripLeadingCommand(text)
        R.AddUnique(variants, "font " .. text)
        R.AddUnique(variants, "set font " .. text)
        if noun ~= "" and noun ~= R.Normalize(text) then
            R.AddUnique(variants, "set font " .. noun)
            R.AddUnique(variants, "change font " .. noun)
        end
    elseif M.activeKey == "opt_colors" then
        R.AddUnique(variants, text .. " color")
        R.AddUnique(variants, "set " .. text)
        R.AddUnique(variants, "global " .. text)
    else
        local noun = R.StripLeadingCommand(text)
        local relativeVerb = R.LeadingRelativeCommand(text)
        for i = 1, #prefixes do
            local scopedPrefix = prefixes[i]
            R.AddBooleanContextVariants(variants, scopedPrefix, text)
            R.AddUnique(variants, scopedPrefix .. " " .. text)
            R.AddUnique(variants, "set " .. scopedPrefix .. " " .. text)
            if noun ~= "" and noun ~= R.Normalize(text) then
                if relativeVerb then R.AddUnique(variants, relativeVerb .. " " .. scopedPrefix .. " " .. noun) end
                R.AddUnique(variants, "set " .. scopedPrefix .. " " .. noun)
                R.AddUnique(variants, "change " .. scopedPrefix .. " " .. noun)
            end
        end
    end
    return #variants > 0 and variants or nil
end

function R.TryContext(text, coreHandler)    if type(coreHandler) ~= "function" then return nil end
    local variants = R.ContextualVariants(text)
    if not variants then return nil end
    local basePending = A.RouterSnapshotPendingState()
    local bestAmbiguous
    local bestAmbiguousPending
    for i = 1, #variants do
        R.MaybeYield()
        local result = coreHandler(variants[i])
        if result and not A.RouterIsUnknownResult(result) then
            if not A.RouterIsAmbiguousResult(result) then
                if result.summary == nil or result.summary == "" or result.summary == "MSUF options change." then
                    result.summary = "Current-page context: " .. R.CurrentPageSummaryLabel()
                end
                return result
            end
            local ambiguousPending = A.RouterSnapshotPendingState()
            A.RouterRestorePendingState(basePending)
            bestAmbiguous = bestAmbiguous or result
            bestAmbiguousPending = bestAmbiguousPending or ambiguousPending
        else
            A.RouterRestorePendingState(basePending)
        end
    end
    if bestAmbiguous and bestAmbiguousPending then A.RouterRestorePendingState(bestAmbiguousPending) end
    return bestAmbiguous
end

function R.MutationFallbackVariants(text)    local norm = R.Normalize(text)
    local variants = {}
    if norm == "" then return variants end

    if R.ContainsAny(norm, { "frame outline", "frame border", "unitframe outline", "unitframe border" }) then
        R.AddUnique(variants, norm:gsub("frame%s+outline", "bar outline"))
        R.AddUnique(variants, norm:gsub("frame%s+border", "bar border"))
        R.AddUnique(variants, norm:gsub("unitframe%s+outline", "bar outline"))
        R.AddUnique(variants, norm:gsub("unitframe%s+border", "bar border"))
        R.AddUnique(variants, "global bar " .. norm)
    end

    if R.ContainsAny(norm, { "open", "oeffne" }) then
        R.AddUnique(variants, norm:gsub("^oeffne%s+", "open "))
    end

    if R.ContainsAny(norm, { "turn off", "turn on", "enable", "disable", "show", "hide", "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden" }) then
        R.AddUnique(variants, norm:gsub("^turn%s+off%s+", "disable "))
        R.AddUnique(variants, norm:gsub("^turn%s+on%s+", "enable "))
        R.AddUnique(variants, norm:gsub("^show%s+", "turn on "))
        R.AddUnique(variants, norm:gsub("^hide%s+", "turn off "))
        R.AddUnique(variants, norm:gsub("^disable%s+", "turn off "))
        R.AddUnique(variants, norm:gsub("^enable%s+", "turn on "))
        R.AddUnique(variants, norm:gsub("^ausschalten%s+", "turn off "))
        R.AddUnique(variants, norm:gsub("^ausblenden%s+", "turn off "))
        R.AddUnique(variants, norm:gsub("^einschalten%s+", "turn on "))
        R.AddUnique(variants, norm:gsub("^einblenden%s+", "turn on "))
    end

    return variants
end

function A.RouterTryMutationFallbacks(text, coreHandler)
    if type(coreHandler) ~= "function" then return nil end
    local variants = R.MutationFallbackVariants(text)
    local limit = math.min(#variants, 4)
    for i = 1, limit do
        R.MaybeYield()
        if variants[i] ~= R.Normalize(text) then
            local result = coreHandler(variants[i])
            if result and not A.RouterIsUnknownResult(result) then
                result.summary = result.summary or "Matched by a wording shortcut."
                return result
            end
        end
    end
    return nil
end

function A.RouterLooksLikeExplicitSearchRequest(text)
    local norm = R.Normalize(text)
    return norm:match("^search%s+") ~= nil
        or norm:match("^search%s+for%s+") ~= nil
        or norm:match("^find%s+") ~= nil
        or norm:match("^find%s+me%s+") ~= nil
        or norm:match("^look%s+for%s+") ~= nil
        or norm:match("^suche%s+") ~= nil
        or norm:match("^finde%s+") ~= nil
end

function A.RouterLooksLikeExactActionPhrase(text)
    local parser = A.Parser or {}
    if type(parser.ParseExactActionPhraseShortcut) ~= "function" then return false end
    local parsed = parser.ParseExactActionPhraseShortcut(R.Normalize(text), text)
    return type(parsed) == "table" and (parsed.kind == "action" or parsed.kind == "choice")
end

function A.RouterLooksLikePendingChoiceFollowup(text)
    local norm = R.Normalize(text)
    if norm == "" then return false end
    if norm:match("^%d+$") then return true end
    if norm == "what" then return true end
    if R.IsStandaloneCancelReply(norm) then return true end
    if R.ContainsAny(norm, R.FLOW_TERMS) then return true end
    if R.ContainsAny(norm, {
        "option", "choice", "listed option", "listed choice",
        "fix it", "fix that", "apply it", "apply that", "do it", "do that",
        "use it", "use that", "select it", "select that", "pick it", "pick that",
        "open it", "open that", "open this", "open option", "open choice",
        "explain it", "explain that", "explain this", "explain option", "explain choice",
        "why this", "why that", "why it", "tell me more", "more details",
        "current value", "value now", "simple explanation", "explain it simpler",
    }) then
        return true
    end
    if R.ContainsAny(norm, { "it", "this", "that" })
        and R.ContainsAny(norm, { "open", "show", "explain", "describe", "why", "apply", "use", "select", "pick", "run" })
    then
        return true
    end
    return false
end

function A.RouterLooksLikePendingChoiceTopicSwitch(text)
    local norm = R.Normalize(text)
    if norm == "" or A.RouterLooksLikePendingChoiceFollowup(norm) then return false end
    if A.RouterLooksLikeExplicitSearchRequest(norm) then return true end
    if R.ContainsAny(norm, {
        "run checks", "run check", "run diagnostics", "health check",
        "profile status", "show profile summary", "assistant support text",
    }) then
        return true
    end
    if R.LooksLikeBugReportRequest(norm) or R.LooksLikeGuidedTourRequest(norm) then return true end
    if R.ContainsAny(norm, { "here", "this page", "current page", "page help" })
        and R.ContainsAny(norm, { "help", "commands", "what can", "what settings", "explain", "how can", "how do", "where can", "where do" })
    then
        return true
    end
    if R.LooksLikeKnowledgeQuestionPrefix(norm)
        or R.LooksLikeLocalWowUiKnowledgeRequest(norm)
        or R.LooksLikeScopedHelpKnowledgeRequest(norm)
        or R.LooksLikeKnowledgeFirstRequest(norm)
    then
        return true
    end
    if R.LooksLikeRoleGuidanceRequest(norm)
        or R.LooksLikeContentGuidanceRequest(norm)
        or R.LooksLikeClassGuidanceRequest(norm)
    then
        return true
    end
    if R.TrySignalProblemShortcut(norm) or R.TryReadabilityShortcut(norm) or R.TryColorContrastShortcut(norm) then
        return true
    end
    if A.RouterTryAssistantUsabilityProblemShortcut and A.RouterTryAssistantUsabilityProblemShortcut(norm, nil) then return true end
    if A.RouterTryDecisionGuidanceShortcut and A.RouterTryDecisionGuidanceShortcut(norm, nil) then return true end
    if A.RouterTrySafePlanningShortcut and A.RouterTrySafePlanningShortcut(norm, nil) then return true end
    if A.RouterLooksLikeVisualSettingTopic and A.RouterLooksLikeVisualSettingTopic(norm) then return true end
    if A.RouterLooksLikeMovementSettingTopic and A.RouterLooksLikeMovementSettingTopic(norm) then return true end
    if A.RouterLooksLikeUnitFrameSettingTopic and A.RouterLooksLikeUnitFrameSettingTopic(norm) then return true end
    if R.LooksLikeRegistrySettingDecisionQuestion and R.LooksLikeRegistrySettingDecisionQuestion(norm) then return true end
    if R.LooksLikeRegistrySettingCurrentValueQuestion and R.LooksLikeRegistrySettingCurrentValueQuestion(norm) then return true end
    if R.LooksLikeRegistrySettingExplainQuestion and R.LooksLikeRegistrySettingExplainQuestion(norm) then return true end
    if R.LooksLikeRegistrySettingTroubleshootingQuestion and R.LooksLikeRegistrySettingTroubleshootingQuestion(norm) then return true end
    if R.LooksLikeRegistrySettingLocationQuestion and R.LooksLikeRegistrySettingLocationQuestion(norm) then return true end
    if A.RouterTryEditModeProblemShortcut and A.RouterTryEditModeProblemShortcut(norm, nil) then return true end
    if A.RouterTryProfileProblemShortcut and A.RouterTryProfileProblemShortcut(norm, nil) then return true end
    if A.RouterTryGroupLayoutProblemShortcut and A.RouterTryGroupLayoutProblemShortcut(norm, nil) then return true end
    if A.RouterTryAuraProblemShortcut and A.RouterTryAuraProblemShortcut(norm, nil) then return true end
    if A.RouterTryCastbarProblemShortcut and A.RouterTryCastbarProblemShortcut(norm, nil) then return true end
    if A.RouterTryTextPowerProblemShortcut and A.RouterTryTextPowerProblemShortcut(norm, nil) then return true end
    if A.RouterTryUnitFrameProblemShortcut and A.RouterTryUnitFrameProblemShortcut(norm, nil) then return true end
    if A.RouterTryIndicatorProblemShortcut and A.RouterTryIndicatorProblemShortcut(norm, nil) then return true end
    if A.RouterTryClassResourceProblemShortcut and A.RouterTryClassResourceProblemShortcut(norm, nil) then return true end
    if A.RouterTryGameplayProblemShortcut and A.RouterTryGameplayProblemShortcut(norm, nil) then return true end
    if A.RouterLooksLikeMiscProblemTopic and A.RouterLooksLikeMiscProblemTopic(norm) then return true end
    if (R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS))
        and (R.ContainsAny(norm, R.NATURAL_GENERIC_PROBLEM_TOPICS)
            or R.ContainsAny(norm, R.NATURAL_CONCRETE_VISIBILITY_TOPICS)
            or R.ContainsAny(norm, R.VISIBILITY_AURA_TERMS)
            or R.ContainsAny(norm, R.VISIBILITY_CASTBAR_TERMS))
    then
        return true
    end
    return false
end

function A.RouteInput(text, coreHandler)
    text = R.Trim(text)
    if text == "" then return nil end
    R.ClearStaleHelpContextForInput(text)

    local hasCore = type(coreHandler) == "function"
    local coreCache = {}
    local function Core(value)
        if not hasCore then return nil end
        value = R.Trim(value)
        if coreCache[value] == nil then
            local result = coreHandler(value)
            coreCache[value] = result or false
        end
        return coreCache[value] ~= false and coreCache[value] or nil
    end

    local hasPendingState = A.RouterHasPendingAssistantState()
    local hasBlockingPendingState = A.RouterHasBlockingPendingAssistantState()
    local hasPendingChoices = A.RouterHasPendingChoices()
    local hasPendingResults = A.RouterHasPendingSearchResults()
    local pendingResultReply = hasPendingResults and R.LooksLikePendingResultReply(text)
    local auraFilterAnswerIntent = A.RouterTryAuraFilterStatusShortcut
        and R.AuraFilterStatusWantsAnswer
        and R.AuraFilterStatusWantsAnswer(text)
    if auraFilterAnswerIntent
        and not R.ContainsAny(text, { "result", "results", "option", "options", "entry", "entries" })
    then
        pendingResultReply = false
    end
    local explicitSearchRequest = A.RouterLooksLikeExplicitSearchRequest(text)
    if hasPendingChoices
        and not pendingResultReply
        and not A.RouterHasPendingConfirmationOrFlow()
        and A.RouterLooksLikePendingChoiceTopicSwitch(text)
    then
        A.RouterClearPendingChoicesForRoute()
        hasPendingState = A.RouterHasPendingAssistantState()
        hasBlockingPendingState = A.RouterHasBlockingPendingAssistantState()
        hasPendingChoices = A.RouterHasPendingChoices()
    end
    if R.IsExactGenericDiagnosticRequest(text) and not pendingResultReply then
        local diagnosticResult = Core(text)
        if diagnosticResult then return diagnosticResult end
    end
    if not hasPendingState and not pendingResultReply and R.IsStandaloneCancelReply(text) then
        return {
            text = "Cancelled. Nothing was waiting for confirmation or a choice.",
            status = "info",
            summary = "Assistant conversation",
        }
    end

    if not hasBlockingPendingState and not pendingResultReply then
        local earlyPageHelpResult = R.TryPageHelpShortcut(text, Core)
        if earlyPageHelpResult then return earlyPageHelpResult end

        local earlyLastChangeSettingFollowupResult = R.TryLastChangeSettingFollowup and R.TryLastChangeSettingFollowup(text)
        if earlyLastChangeSettingFollowupResult then return earlyLastChangeSettingFollowupResult end

        local earlyAuraFilterStatusResult = A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(text)
        if earlyAuraFilterStatusResult then return earlyAuraFilterStatusResult end

        local earlyRegistrySettingCurrentValueResult = A.RouterTryRegistrySettingCurrentValueShortcut and A.RouterTryRegistrySettingCurrentValueShortcut(text, Core)
        if earlyRegistrySettingCurrentValueResult then return earlyRegistrySettingCurrentValueResult end
    end

    if not hasBlockingPendingState and not pendingResultReply
        and R.LooksLikeDirectDefinitionQuestion(text)
        and A.Knowledge and type(A.Knowledge.Answer) == "function"
    then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    local safePlanningOverride = A.RouterTrySafePlanningShortcut and A.RouterTrySafePlanningShortcut(text, Core)
    if safePlanningOverride and (pendingResultReply or hasPendingState or not hasBlockingPendingState) then
        return safePlanningOverride
    end

    local safePlanningFollowupOverride = (not hasPendingState) and (not pendingResultReply) and A.RouterTrySafePlanningFollowup and A.RouterTrySafePlanningFollowup(text, Core)
    if safePlanningFollowupOverride then return safePlanningFollowupOverride end

    if not hasBlockingPendingState and not pendingResultReply then
        local crossFrameTextResult = A.RouterTryCrossFrameTextRequestShortcut and A.RouterTryCrossFrameTextRequestShortcut(text, Core)
        if crossFrameTextResult then return crossFrameTextResult end

        local targetTargetInlineNameResult = A.RouterTryTargetTargetInlineNameShortcut and A.RouterTryTargetTargetInlineNameShortcut(text, Core)
        if targetTargetInlineNameResult then return targetTargetInlineNameResult end

        local dependentTargetTroubleshootingResult = A.RouterTryDependentTargetTroubleshootingShortcut and A.RouterTryDependentTargetTroubleshootingShortcut(text, Core)
        if dependentTargetTroubleshootingResult then return dependentTargetTroubleshootingResult end

        local crossFrameVisualResult = A.RouterTryCrossFrameVisualRequestShortcut and A.RouterTryCrossFrameVisualRequestShortcut(text, Core)
        if crossFrameVisualResult then return crossFrameVisualResult end

        local assistantUsabilityResult = A.RouterTryAssistantUsabilityProblemShortcut and A.RouterTryAssistantUsabilityProblemShortcut(text, Core)
        if assistantUsabilityResult then return assistantUsabilityResult end

        local decisionGuidanceResult = A.RouterTryDecisionGuidanceShortcut and A.RouterTryDecisionGuidanceShortcut(text, Core)
        if decisionGuidanceResult then return decisionGuidanceResult end

        local safePlanningResult = A.RouterTrySafePlanningShortcut and A.RouterTrySafePlanningShortcut(text, Core)
        if safePlanningResult then return safePlanningResult end

        local lastChangeSettingFollowupResult = R.TryLastChangeSettingFollowup and R.TryLastChangeSettingFollowup(text)
        if lastChangeSettingFollowupResult then return lastChangeSettingFollowupResult end

        local auraFilterStatusResult = A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(text)
        if auraFilterStatusResult then return auraFilterStatusResult end

        local registrySettingCurrentValueResult = A.RouterTryRegistrySettingCurrentValueShortcut and A.RouterTryRegistrySettingCurrentValueShortcut(text, Core)
        if registrySettingCurrentValueResult then return registrySettingCurrentValueResult end

        local registrySettingDecisionResult = A.RouterTryRegistrySettingDecisionShortcut and A.RouterTryRegistrySettingDecisionShortcut(text, Core)
        if registrySettingDecisionResult then return registrySettingDecisionResult end

        local registrySettingExplainResult = A.RouterTryRegistrySettingExplainShortcut and A.RouterTryRegistrySettingExplainShortcut(text, Core)
        if registrySettingExplainResult then return registrySettingExplainResult end

        local registrySettingTroubleshootingResult = A.RouterTryRegistrySettingTroubleshootingShortcut and A.RouterTryRegistrySettingTroubleshootingShortcut(text, Core)
        if registrySettingTroubleshootingResult then return registrySettingTroubleshootingResult end

        local visualSettingResult = A.RouterTryVisualSettingShortcut and A.RouterTryVisualSettingShortcut(text, Core)
        if visualSettingResult then return visualSettingResult end

        local movementSettingResult = A.RouterTryMovementSettingShortcut and A.RouterTryMovementSettingShortcut(text, Core)
        if movementSettingResult then return movementSettingResult end

        local unitFrameSettingResult = A.RouterTryUnitFrameSettingShortcut and A.RouterTryUnitFrameSettingShortcut(text, Core)
        if unitFrameSettingResult then return unitFrameSettingResult end

        local correctionResult = R.TryCorrectionShortcut(text, Core)
        if correctionResult then return correctionResult end
    end

    if hasBlockingPendingState and not pendingResultReply then
        local blockingProfileHelpResult = A.RouterTryProfileProblemShortcut and A.RouterTryProfileProblemShortcut(text, nil)
        if blockingProfileHelpResult then return blockingProfileHelpResult end
    end

    if hasPendingState and not hasBlockingPendingState and not pendingResultReply then
        local pendingHelpContextResult = R.TryHelpContextFollowup(text, Core)
        if pendingHelpContextResult then return pendingHelpContextResult end

        if R.LooksLikeBugReportRequest(text) then return R.BugReportReply(text) end

        local pendingCrossFrameTextResult = A.RouterTryCrossFrameTextRequestShortcut and A.RouterTryCrossFrameTextRequestShortcut(text, Core)
        if pendingCrossFrameTextResult then return pendingCrossFrameTextResult end

        local pendingTargetTargetInlineNameResult = A.RouterTryTargetTargetInlineNameShortcut and A.RouterTryTargetTargetInlineNameShortcut(text, Core)
        if pendingTargetTargetInlineNameResult then return pendingTargetTargetInlineNameResult end

        local pendingDependentTargetTroubleshootingResult = A.RouterTryDependentTargetTroubleshootingShortcut and A.RouterTryDependentTargetTroubleshootingShortcut(text, Core)
        if pendingDependentTargetTroubleshootingResult then return pendingDependentTargetTroubleshootingResult end

        local pendingCrossFrameVisualResult = A.RouterTryCrossFrameVisualRequestShortcut and A.RouterTryCrossFrameVisualRequestShortcut(text, Core)
        if pendingCrossFrameVisualResult then return pendingCrossFrameVisualResult end

        local pendingAssistantUsabilityResult = A.RouterTryAssistantUsabilityProblemShortcut and A.RouterTryAssistantUsabilityProblemShortcut(text, Core)
        if pendingAssistantUsabilityResult then return pendingAssistantUsabilityResult end

        local pendingDecisionGuidanceResult = A.RouterTryDecisionGuidanceShortcut and A.RouterTryDecisionGuidanceShortcut(text, Core)
        if pendingDecisionGuidanceResult then return pendingDecisionGuidanceResult end

        local pendingSafePlanningResult = A.RouterTrySafePlanningShortcut and A.RouterTrySafePlanningShortcut(text, Core)
        if pendingSafePlanningResult then return pendingSafePlanningResult end

        local pendingLastChangeSettingFollowupResult = R.TryLastChangeSettingFollowup and R.TryLastChangeSettingFollowup(text)
        if pendingLastChangeSettingFollowupResult then return pendingLastChangeSettingFollowupResult end

        local pendingAuraFilterStatusResult = A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(text)
        if pendingAuraFilterStatusResult then return pendingAuraFilterStatusResult end

        local pendingRegistrySettingCurrentValueResult = A.RouterTryRegistrySettingCurrentValueShortcut and A.RouterTryRegistrySettingCurrentValueShortcut(text, Core)
        if pendingRegistrySettingCurrentValueResult then return pendingRegistrySettingCurrentValueResult end

        local pendingRegistrySettingDecisionResult = A.RouterTryRegistrySettingDecisionShortcut and A.RouterTryRegistrySettingDecisionShortcut(text, Core)
        if pendingRegistrySettingDecisionResult then return pendingRegistrySettingDecisionResult end

        local pendingRegistrySettingExplainResult = A.RouterTryRegistrySettingExplainShortcut and A.RouterTryRegistrySettingExplainShortcut(text, Core)
        if pendingRegistrySettingExplainResult then return pendingRegistrySettingExplainResult end

        local pendingRegistrySettingTroubleshootingResult = A.RouterTryRegistrySettingTroubleshootingShortcut and A.RouterTryRegistrySettingTroubleshootingShortcut(text, Core)
        if pendingRegistrySettingTroubleshootingResult then return pendingRegistrySettingTroubleshootingResult end

        local pendingVisualSettingResult = A.RouterTryVisualSettingShortcut and A.RouterTryVisualSettingShortcut(text, Core)
        if pendingVisualSettingResult then return pendingVisualSettingResult end

        local pendingMovementSettingResult = A.RouterTryMovementSettingShortcut and A.RouterTryMovementSettingShortcut(text, Core)
        if pendingMovementSettingResult then return pendingMovementSettingResult end

        local pendingUnitFrameSettingResult = A.RouterTryUnitFrameSettingShortcut and A.RouterTryUnitFrameSettingShortcut(text, Core)
        if pendingUnitFrameSettingResult then return pendingUnitFrameSettingResult end

        local pendingEditModeProblemResult = A.RouterTryEditModeProblemShortcut and A.RouterTryEditModeProblemShortcut(text, Core)
        if pendingEditModeProblemResult then return pendingEditModeProblemResult end

        local pendingProfileProblemResult = A.RouterTryProfileProblemShortcut and A.RouterTryProfileProblemShortcut(text, Core)
        if pendingProfileProblemResult then return pendingProfileProblemResult end

        local pendingGroupLayoutProblemResult = A.RouterTryGroupLayoutProblemShortcut and A.RouterTryGroupLayoutProblemShortcut(text, Core)
        if pendingGroupLayoutProblemResult then return pendingGroupLayoutProblemResult end

        local pendingAuraProblemResult = A.RouterTryAuraProblemShortcut and A.RouterTryAuraProblemShortcut(text, Core)
        if pendingAuraProblemResult then return pendingAuraProblemResult end

        local pendingCastbarProblemResult = A.RouterTryCastbarProblemShortcut and A.RouterTryCastbarProblemShortcut(text, Core)
        if pendingCastbarProblemResult then return pendingCastbarProblemResult end

        local pendingTextPowerProblemResult = A.RouterTryTextPowerProblemShortcut and A.RouterTryTextPowerProblemShortcut(text, Core)
        if pendingTextPowerProblemResult then return pendingTextPowerProblemResult end

        local pendingUnitFrameProblemResult = A.RouterTryUnitFrameProblemShortcut and A.RouterTryUnitFrameProblemShortcut(text, Core)
        if pendingUnitFrameProblemResult then return pendingUnitFrameProblemResult end

        local pendingIndicatorProblemResult = A.RouterTryIndicatorProblemShortcut and A.RouterTryIndicatorProblemShortcut(text, Core)
        if pendingIndicatorProblemResult then return pendingIndicatorProblemResult end

        local pendingClassResourceProblemResult = A.RouterTryClassResourceProblemShortcut and A.RouterTryClassResourceProblemShortcut(text, Core)
        if pendingClassResourceProblemResult then return pendingClassResourceProblemResult end

        local pendingGameplayProblemResult = A.RouterTryGameplayProblemShortcut and A.RouterTryGameplayProblemShortcut(text, Core)
        if pendingGameplayProblemResult then return pendingGameplayProblemResult end

        local pendingRegistrySettingLocationResult = A.RouterTryRegistrySettingLocationShortcut and A.RouterTryRegistrySettingLocationShortcut(text, Core)
        if pendingRegistrySettingLocationResult then return pendingRegistrySettingLocationResult end

        local pendingNaturalProblemResult = R.TryNaturalProblemShortcut(text, Core)
        if pendingNaturalProblemResult then return pendingNaturalProblemResult end

        local pendingMiscProblemResult = A.RouterTryMiscProblemShortcut and A.RouterTryMiscProblemShortcut(text, Core)
        if pendingMiscProblemResult then return pendingMiscProblemResult end

        local pendingSignalProblemResult = R.TrySignalProblemShortcut(text)
        if pendingSignalProblemResult then return pendingSignalProblemResult end

        local pendingVisibilityResult = R.TryVisibilityDiagnosticShortcut(text, Core)
        if pendingVisibilityResult then return pendingVisibilityResult end

        local pendingColorContrastResult = R.TryColorContrastShortcut(text)
        if pendingColorContrastResult then return pendingColorContrastResult end

        local pendingReadabilityResult = R.TryReadabilityShortcut(text)
        if pendingReadabilityResult then return pendingReadabilityResult end
    end

    -- Pending confirmations/choices/flows must always win. Guided setup is lighter:
    -- it can answer short follow-ups, but unknown core replies should fall through.
    if hasCore and (
        pendingResultReply
        or (hasPendingState and not (not hasBlockingPendingState and explicitSearchRequest))
        or (R.IsStandaloneFlowReply(text) and not R.LooksLikeKnowledgeQuestionPrefix(text))
    ) then
        local pendingResult = Core(text)
        if pendingResult and (not A.RouterIsUnknownResult(pendingResult) or hasBlockingPendingState) then return pendingResult end
    end

    local earlyHelpContextResult = R.TryHelpContextFollowup(text, Core)
    if earlyHelpContextResult then return earlyHelpContextResult end

    if R.LooksLikeBugReportRequest(text) then return R.BugReportReply(text) end

    local crossFrameTextProblemResult = A.RouterTryCrossFrameTextRequestShortcut and A.RouterTryCrossFrameTextRequestShortcut(text, Core)
    if crossFrameTextProblemResult then return crossFrameTextProblemResult end

    local targetTargetInlineNameProblemResult = A.RouterTryTargetTargetInlineNameShortcut and A.RouterTryTargetTargetInlineNameShortcut(text, Core)
    if targetTargetInlineNameProblemResult then return targetTargetInlineNameProblemResult end

    local dependentTargetTroubleshootingResult = A.RouterTryDependentTargetTroubleshootingShortcut and A.RouterTryDependentTargetTroubleshootingShortcut(text, Core)
    if dependentTargetTroubleshootingResult then return dependentTargetTroubleshootingResult end

    local crossFrameVisualProblemResult = A.RouterTryCrossFrameVisualRequestShortcut and A.RouterTryCrossFrameVisualRequestShortcut(text, Core)
    if crossFrameVisualProblemResult then return crossFrameVisualProblemResult end

    local assistantUsabilityProblemResult = A.RouterTryAssistantUsabilityProblemShortcut and A.RouterTryAssistantUsabilityProblemShortcut(text, Core)
    if assistantUsabilityProblemResult then return assistantUsabilityProblemResult end

    local decisionGuidanceProblemResult = A.RouterTryDecisionGuidanceShortcut and A.RouterTryDecisionGuidanceShortcut(text, Core)
    if decisionGuidanceProblemResult then return decisionGuidanceProblemResult end

    local safePlanningProblemResult = A.RouterTrySafePlanningShortcut and A.RouterTrySafePlanningShortcut(text, Core)
    if safePlanningProblemResult then return safePlanningProblemResult end

    local lastChangeSettingFollowupProblemResult = R.TryLastChangeSettingFollowup and R.TryLastChangeSettingFollowup(text)
    if lastChangeSettingFollowupProblemResult then return lastChangeSettingFollowupProblemResult end

    local auraFilterStatusProblemResult = A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(text)
    if auraFilterStatusProblemResult then return auraFilterStatusProblemResult end

    local registrySettingCurrentValueProblemResult = A.RouterTryRegistrySettingCurrentValueShortcut and A.RouterTryRegistrySettingCurrentValueShortcut(text, Core)
    if registrySettingCurrentValueProblemResult then return registrySettingCurrentValueProblemResult end

    local registrySettingDecisionProblemResult = A.RouterTryRegistrySettingDecisionShortcut and A.RouterTryRegistrySettingDecisionShortcut(text, Core)
    if registrySettingDecisionProblemResult then return registrySettingDecisionProblemResult end

    local registrySettingExplainProblemResult = A.RouterTryRegistrySettingExplainShortcut and A.RouterTryRegistrySettingExplainShortcut(text, Core)
    if registrySettingExplainProblemResult then return registrySettingExplainProblemResult end

    local registrySettingTroubleshootingProblemResult = A.RouterTryRegistrySettingTroubleshootingShortcut and A.RouterTryRegistrySettingTroubleshootingShortcut(text, Core)
    if registrySettingTroubleshootingProblemResult then return registrySettingTroubleshootingProblemResult end

    local visualSettingProblemResult = A.RouterTryVisualSettingShortcut and A.RouterTryVisualSettingShortcut(text, Core)
    if visualSettingProblemResult then return visualSettingProblemResult end

    local movementSettingProblemResult = A.RouterTryMovementSettingShortcut and A.RouterTryMovementSettingShortcut(text, Core)
    if movementSettingProblemResult then return movementSettingProblemResult end

    local unitFrameSettingProblemResult = A.RouterTryUnitFrameSettingShortcut and A.RouterTryUnitFrameSettingShortcut(text, Core)
    if unitFrameSettingProblemResult then return unitFrameSettingProblemResult end

    local editModeProblemResult = A.RouterTryEditModeProblemShortcut and A.RouterTryEditModeProblemShortcut(text, Core)
    if editModeProblemResult then return editModeProblemResult end

    local profileProblemResult = A.RouterTryProfileProblemShortcut and A.RouterTryProfileProblemShortcut(text, Core)
    if profileProblemResult then return profileProblemResult end

    local groupLayoutProblemResult = A.RouterTryGroupLayoutProblemShortcut and A.RouterTryGroupLayoutProblemShortcut(text, Core)
    if groupLayoutProblemResult then return groupLayoutProblemResult end

    local auraProblemResult = A.RouterTryAuraProblemShortcut and A.RouterTryAuraProblemShortcut(text, Core)
    if auraProblemResult then return auraProblemResult end

    local castbarProblemResult = A.RouterTryCastbarProblemShortcut and A.RouterTryCastbarProblemShortcut(text, Core)
    if castbarProblemResult then return castbarProblemResult end

    local textPowerProblemResult = A.RouterTryTextPowerProblemShortcut and A.RouterTryTextPowerProblemShortcut(text, Core)
    if textPowerProblemResult then return textPowerProblemResult end

    local unitFrameProblemResult = A.RouterTryUnitFrameProblemShortcut and A.RouterTryUnitFrameProblemShortcut(text, Core)
    if unitFrameProblemResult then return unitFrameProblemResult end

    local indicatorProblemResult = A.RouterTryIndicatorProblemShortcut and A.RouterTryIndicatorProblemShortcut(text, Core)
    if indicatorProblemResult then return indicatorProblemResult end

    local classResourceProblemResult = A.RouterTryClassResourceProblemShortcut and A.RouterTryClassResourceProblemShortcut(text, Core)
    if classResourceProblemResult then return classResourceProblemResult end

    local gameplayProblemResult = A.RouterTryGameplayProblemShortcut and A.RouterTryGameplayProblemShortcut(text, Core)
    if gameplayProblemResult then return gameplayProblemResult end

    local registrySettingLocationProblemResult = A.RouterTryRegistrySettingLocationShortcut and A.RouterTryRegistrySettingLocationShortcut(text, Core)
    if registrySettingLocationProblemResult then return registrySettingLocationProblemResult end

    local naturalProblemResult = R.TryNaturalProblemShortcut(text, Core)
    if naturalProblemResult then return naturalProblemResult end

    local miscProblemResult = A.RouterTryMiscProblemShortcut and A.RouterTryMiscProblemShortcut(text, Core)
    if miscProblemResult then return miscProblemResult end

    local signalProblemResult = R.TrySignalProblemShortcut(text)
    if signalProblemResult then return signalProblemResult end

    local visibilityResult = R.TryVisibilityDiagnosticShortcut(text, Core)
    if visibilityResult then return visibilityResult end

    local colorContrastResult = R.TryColorContrastShortcut(text)
    if colorContrastResult then return colorContrastResult end

    local readabilityResult = R.TryReadabilityShortcut(text)
    if readabilityResult then return readabilityResult end

    local pageHelpResult = R.TryPageHelpShortcut(text, Core)
    if pageHelpResult then return pageHelpResult end

    local pageLocationResult = R.TryPageLocationShortcut(text, Core)
    if pageLocationResult then return pageLocationResult end

    local registrySettingLocationResult = A.RouterTryRegistrySettingLocationShortcut and A.RouterTryRegistrySettingLocationShortcut(text, Core)
    if registrySettingLocationResult then return registrySettingLocationResult end

    local lateRegistrySettingExplainResult = A.RouterTryRegistrySettingExplainShortcut and A.RouterTryRegistrySettingExplainShortcut(text, Core)
    if lateRegistrySettingExplainResult then return lateRegistrySettingExplainResult end

    if R.LooksLikeScopedHelpKnowledgeRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    local helpContextResult = R.TryHelpContextFollowup(text, Core)
    if helpContextResult then return helpContextResult end

    local generalGuidanceResult = R.TryGeneralGuidanceShortcut(text, Core)
    if generalGuidanceResult then return generalGuidanceResult end

    if R.LooksLikeGuidedTourRequest(text) and hasCore then
        local guidedResult = Core(text)
        if guidedResult and not A.RouterIsUnknownResult(guidedResult) then return guidedResult end
    end

    if not hasBlockingPendingState and not pendingResultReply and explicitSearchRequest
        and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey, forceSearch = true })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if not hasBlockingPendingState and not pendingResultReply and R.LooksLikeLocalWowUiKnowledgeRequest(text)
        and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if not hasBlockingPendingState and not pendingResultReply and hasCore and A.RouterLooksLikeExactActionPhrase(text) then
        local actionPhraseResult = Core(text)
        if actionPhraseResult and not A.RouterIsUnknownResult(actionPhraseResult) then return actionPhraseResult end
    end

    local humanResult = R.HumanConversationReply(text)
    if humanResult then return humanResult end

    if hasCore and R.LooksLikeExactAssistantKey(text) and (R.LooksLikeMutation(text) or R.StartsWithMutationCommand(text)) then
        local exactKeyResult = Core(text)
        if exactKeyResult and not A.RouterIsUnknownResult(exactKeyResult) then return exactKeyResult end
    end

    if not R.LooksLikeKnowledgeQuestionPrefix(text) then
        local parser = A.Parser or {}
        local broadAnchor = parser.ParseBroadHumanAnchorTargetAnswer and parser.ParseBroadHumanAnchorTargetAnswer(R.Normalize(text), text)
        if broadAnchor then return broadAnchor end
    end

    if hasCore and not R.LooksLikeKnowledgeQuestionPrefix(text)
        and not (R.Normalize(text):find("%d+%.%d+") or R.ContainsAny(text, {
            "release", "version", "preview", "alpha", "beta", "patch", "build", "changelog", "change log",
        }))
        and R.ContainsAny(text, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change",
    }) then
        local followupResult = Core(text)
        if followupResult and not A.RouterIsUnknownResult(followupResult) then return followupResult end
    end

    if R.LooksLikeKnowledgeFirstRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    local parser = A.Parser or {}
    local normForScope = R.Normalize(text)
    local hasClassPowerScope = (type(parser.CLASS_POWER_TERMS) == "table" and R.ContainsAny(normForScope, parser.CLASS_POWER_TERMS))
        or R.ContainsAny(normForScope, { "resource numbers", "resource number", "resource text", "resource texts" })
    local hasExplicitScope = R.ContainsAny(normForScope, {
        "unitframe", "unitframes", "unit frame", "unit frames",
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    })
        or hasClassPowerScope
        or (type(parser.DetectUnits) == "function" and #(parser.DetectUnits(text) or {}) > 0)
        or (type(parser.DetectGroups) == "function" and #(parser.DetectGroups(text) or {}) > 0)
    if hasExplicitScope and hasCore and not R.LooksLikeKnowledgeFirstRequest(text) then
        local scopedCoreResult = Core(text)
        if scopedCoreResult and not A.RouterIsUnknownResult(scopedCoreResult) then return scopedCoreResult end
    end

    -- Short page-local commands become useful before falling back to broad global matching.
    local contextResult = R.TryContext(text, Core)
    if contextResult and not A.RouterIsUnknownResult(contextResult) then return contextResult end

    local coreResult
    if (R.LooksLikeMutation(text) or R.StartsWithMutationCommand(text)) and hasCore then
        coreResult = Core(text)
        if not A.RouterIsUnknownResult(coreResult) then return coreResult end
    end

    -- Release-note questions must not be mistaken for "what did you just change?" follow-ups.
    if R.LooksLikeChangelogKnowledgeRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if R.LooksLikeKnowledgeFirstRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    if hasCore then
        coreResult = coreResult or Core(text)
        if not A.RouterIsUnknownResult(coreResult) then return coreResult end
    end

    if R.LooksLikeBareLookup(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = R.KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    -- Mutation-like commands must not be swallowed by Search/FAQ fallback.
    -- If a setting/action command failed, return the parser failure or suggestions instead of a help article.
    if R.LooksLikeMutation(text) or R.StartsWithMutationCommand(text) then
        local fallbackResult = A.RouterTryMutationFallbacks(text, Core)
        if fallbackResult and not A.RouterIsUnknownResult(fallbackResult) then return fallbackResult end
        local auraUnsupported = R.UnsupportedAuraReply(text)
        if auraUnsupported then return auraUnsupported end
        if A.RouterIsNoClueResult(coreResult) then return A.RouterFriendlyNoMatch(text) end
        return coreResult or { text = "Include a specific frame, page, or option name, or ask for help.", status = "failed" }
    end

    if A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        if R.LooksLikeKnowledgeRequest(text) then
            local noMatch = R.KnowledgeNoMatch(text)
            if noMatch then return noMatch end
        end
    end

    local auraUnsupported = R.UnsupportedAuraReply(text)
    if auraUnsupported then return auraUnsupported end

    if A.RouterIsNoClueResult(coreResult) then return A.RouterFriendlyNoMatch(text) end
    return coreResult or A.RouterFriendlyNoMatch(text)
end
