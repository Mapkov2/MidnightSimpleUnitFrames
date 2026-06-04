local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local COMMAND_TERMS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset", "copy",
    "add", "put", "clear",
    "export", "import", "create", "delete", "remove", "switch", "assign", "rename", "open", "close", "toggle",
    "diagnose", "why", "help", "undo", "redo", "yes", "cancel", "next", "back", "finish", "start", "stop", "enter", "leave",
    "an", "aus", "aktivieren", "deaktivieren", "anzeigen", "verstecken", "verschiebe", "oeffne", "suche", "finde",
}
local COLOR_TERMS = {
    "red", "green", "blue", "yellow", "white", "black", "orange", "purple", "pink", "gold", "gray", "grey",
    "rot", "gruen", "blau", "gelb", "weiss", "schwarz", "lila", "grau",
}
local FLOW_TERMS = {
    "yes", "y", "ja", "confirm", "apply", "cancel", "no", "nein", "abort", "stop", "next", "back", "finish", "undo", "redo",
}

local MUTATION_TERMS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset",
    "copy", "export", "import", "create", "delete", "remove", "add", "put", "clear", "switch", "assign", "rename", "close", "toggle",
    "start", "stop", "enter", "leave", "select", "use", "apply",
    "an", "aus", "aktivieren", "deaktivieren", "anzeigen", "verstecken", "verschiebe",
}
local NAV_HELP_TERMS = {
    "open", "go to", "where", "where is", "where are", "find", "search", "show me", "help", "why", "diagnose", "what", "how",
    "oeffne", "wo", "wo ist", "finde", "suche", "hilfe", "warum", "wie",
}
local EXPLICIT_DOMAIN_TERMS = {
    "player", "target", "focus", "pet", "boss", "targettarget", "target of target", "focustarget", "focus target", "party", "raid", "group", "group frames",
    "spieler", "ziel", "fokus", "begleiter", "gruppe", "gruppenframes",
    "castbar", "cast bar", "auras", "aura", "buff", "debuff", "profile", "profiles", "font", "fonts", "bar", "bars", "class resource", "class power", "gameplay",
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
    auras3 = { prefix = "aura buff", label = "Buffs" },
    auras3_debuffs = { prefix = "aura debuff", label = "Debuffs" },
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

local function HasPhrase(text, phrase)
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
    if ContainsAny(norm, MUTATION_TERMS) then return false end
    if ContainsAny(norm, { "open", "go to", "show settings", "show me settings", "oeffne" }) then return false end
    if ContainsAny(norm, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you set", "last change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
    }) then return false end
    return ContainsAny(norm, {
        "search", "find", "where", "where is", "where are", "faq", "explain",
        "suche", "finde", "wo", "wo ist", "erklaere",
    })
end

local function KnowledgeNoMatch(text)
    if A.Knowledge and type(A.Knowledge.NoMatch) == "function" then
        return A.Knowledge.NoMatch(text)
    end
    return nil
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
    return type(result) == "table" and result.kind == "ambiguous"
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
    if ContainsAny(norm, EXPLICIT_DOMAIN_TERMS) then return true end
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
    out = out:gsub("^on%s+", "")
    out = out:gsub("^off%s+", "")
    out = out:gsub("^enable%s+", "")
    out = out:gsub("^disable%s+", "")
    out = out:gsub("^show%s+", "")
    out = out:gsub("^hide%s+", "")
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
    out = out:gsub("^use%s+", "")
    out = out:gsub("^select%s+", "")
    out = out:gsub("^choose%s+", "")
    return Trim(out)
end

local function AddBooleanContextVariants(variants, prefix, text)
    local norm = Normalize(text)
    local noun = StripBooleanWords(text)
    if noun == "" then return end
    if ContainsAny(norm, { "off", "disable", "disabled", "hide", "aus", "deaktivieren", "verstecken" }) then
        AddUnique(variants, "turn off " .. prefix .. " " .. noun)
        AddUnique(variants, "disable " .. prefix .. " " .. noun)
    elseif ContainsAny(norm, { "on", "enable", "enabled", "show", "an", "aktivieren", "anzeigen" }) then
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
        AddBooleanContextVariants(variants, "castbar", text)
        AddUnique(variants, "castbar " .. text)
        AddUnique(variants, "set castbar " .. text)
        if noun ~= "" and noun ~= Normalize(text) then
            AddUnique(variants, "set castbar " .. noun)
            AddUnique(variants, "change castbar " .. noun)
        end
        AddUnique(variants, "target castbar " .. text)
    elseif M.activeKey == "opt_bars" then
        local noun = StripLeadingCommand(text)
        AddBooleanContextVariants(variants, "bar", text)
        AddUnique(variants, "bar " .. text)
        AddUnique(variants, "set bar " .. text)
        if noun ~= "" and noun ~= Normalize(text) then
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
        for i = 1, #prefixes do
            local scopedPrefix = prefixes[i]
            AddBooleanContextVariants(variants, scopedPrefix, text)
            AddUnique(variants, scopedPrefix .. " " .. text)
            AddUnique(variants, "set " .. scopedPrefix .. " " .. text)
            if noun ~= "" and noun ~= Normalize(text) then
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
    local bestAmbiguous
    for i = 1, #variants do
        local result = coreHandler(variants[i])
        if result and not IsUnknownResult(result) then
            if not IsAmbiguousResult(result) then
                result.summary = result.summary or ("Current-page context: " .. tostring((CurrentPageContext() or {}).label or M.activeKey or "page"))
                return result
            end
            bestAmbiguous = bestAmbiguous or result
        end
    end
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

    if ContainsAny(norm, { "turn off", "turn on", "enable", "disable", "show", "hide", "an", "aus", "aktivieren", "deaktivieren", "anzeigen", "verstecken" }) then
        AddUnique(variants, norm:gsub("^turn%s+off%s+", "disable "))
        AddUnique(variants, norm:gsub("^turn%s+on%s+", "enable "))
        AddUnique(variants, norm:gsub("^show%s+", "turn on "))
        AddUnique(variants, norm:gsub("^hide%s+", "turn off "))
        AddUnique(variants, norm:gsub("^disable%s+", "turn off "))
        AddUnique(variants, norm:gsub("^enable%s+", "turn on "))
    end

    return variants
end

local function TryMutationFallbacks(text, coreHandler)
    if type(coreHandler) ~= "function" then return nil end
    local variants = MutationFallbackVariants(text)
    for i = 1, #variants do
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

    -- Pending confirmations/choices/flows must always win. The core handler owns those.
    if type(coreHandler) == "function" and (HasPendingAssistantState() or ContainsAny(text, FLOW_TERMS)) then
        local pendingResult = coreHandler(text)
        if pendingResult and (not IsUnknownResult(pendingResult) or HasPendingAssistantState()) then return pendingResult end
    end

    -- Short page-local commands become useful before falling back to broad global matching.
    local contextResult = TryContext(text, coreHandler)
    if contextResult and not IsUnknownResult(contextResult) then return contextResult end

    if LooksLikeKnowledgeFirstRequest(text) and A.Knowledge and type(A.Knowledge.Answer) == "function" then
        local answer = A.Knowledge.Answer(text, { currentPage = M and M.activeKey })
        if answer then return answer end
        local noMatch = KnowledgeNoMatch(text)
        if noMatch then return noMatch end
    end

    local coreResult
    if type(coreHandler) == "function" then
        coreResult = coreHandler(text)
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
    if LooksLikeMutation(text) then
        local fallbackResult = TryMutationFallbacks(text, coreHandler)
        if fallbackResult and not IsUnknownResult(fallbackResult) then return fallbackResult end
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

    return coreResult or { text = "I do not know that setting yet.", status = "failed" }
end
