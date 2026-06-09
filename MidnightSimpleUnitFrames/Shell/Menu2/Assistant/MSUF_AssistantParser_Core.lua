local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local normalizeCache = {}
local normalizeCacheCount = 0

local function CacheNormalize(raw, value)
    if #raw <= 180 then
        if normalizeCacheCount > 4096 then
            normalizeCache = {}
            normalizeCacheCount = 0
        end
        if normalizeCache[raw] == nil then normalizeCacheCount = normalizeCacheCount + 1 end
        normalizeCache[raw] = value
    end
    return value
end

local function Normalize(text)
    local raw = tostring(text or "")
    local cached = normalizeCache[raw]
    if cached ~= nil then return cached end
    text = raw:lower()
    text = text:gsub("\195\131\194\164", "ae")
    text = text:gsub("\195\131\194\182", "oe")
    text = text:gsub("\195\131\194\188", "ue")
    text = text:gsub("\195\131\194\159", "ss")
    text = text:gsub("\195\164", "ae")
    text = text:gsub("\195\182", "oe")
    text = text:gsub("\195\188", "ue")
    text = text:gsub("\195\159", "ss")
    text = text:gsub("seperat", "separat")
    text = text:gsub("delimeter", "delimiter")
    text = text:gsub("heigth", "height")
    text = text:gsub("hight", "height")
    text = text:gsub("%f[%w]antoher%f[%W]", "another")
    text = text:gsub("%f[%w]bgu%f[%W]", "bug")
    text = text:gsub("%f[%w]condtion%f[%W]", "condition")
    text = text:gsub("%f[%w]conditoin%f[%W]", "condition")
    text = text:gsub("%f[%w]felher%f[%W]", "fehler")
    text = text:gsub("%f[%w]profie%f[%W]", "profile")
    text = text:gsub("%f[%w]porfile%f[%W]", "profile")
    text = text:gsub("%f[%w]snappign%f[%W]", "snapping")
    text = text:gsub("%f[%w]snaping%f[%W]", "snapping")
    text = text:gsub("%f[%w]snappping%f[%W]", "snapping")
    text = text:gsub("%f[%w]taregt%f[%W]", "target")
    text = text:gsub("%f[%w]teh%f[%W]", "the")
    text = text:gsub("%f[%w]yuo%f[%W]", "you")
    text = text:gsub("interupt", "interrupt")
    text = text:gsub("%f[%w]turn%s+of%f[%W]", "turn off")
    text = text:gsub("first%s+dancer", "first dance")
    text = text:gsub("trennzeichen", "separator")
    text = text:gsub("trenner", "separator")
    text = text:gsub("[\"'`]", "")
    text = text:gsub("[,;:!?%(%)]", " ")
    text = text:gsub("%s+", " ")
    text = Trim(text)
    text = text:gsub("target%s+of%s+target", "targettarget")
    text = text:gsub("target%s+target", "targettarget")
    text = text:gsub("focus%s+target", "focustarget")
    text = text:gsub("cast%s+bar", "castbar")
    text = text:gsub("castbars", "castbar")
    text = text:gsub("powerbars", "power bars")
    text = text:gsub("power%s+bars", "power bar")
    text = text:gsub("powerbar", "power bar")
    text = text:gsub("manabars", "mana bars")
    text = text:gsub("mana%s+bars", "mana bar")
    text = text:gsub("manabar", "mana bar")
    text = text:gsub("unit%s+frames", "unitframes")
    text = text:gsub("gruppen%s+frames", "gruppenframes")
    text = text:gsub("status%s+icons", "status icon")
    text = text:gsub("incoming%s+res%s+", "incoming rez ")
    text = text:gsub("incoming%s+res$", "incoming rez")
    return CacheNormalize(raw, Trim(text))
end
A.Normalize = Normalize

local EXACT_ONLY_FUZZY_WORDS = {
    ["on"] = true,
    ["off"] = true,
    ["no"] = true,
    ["yes"] = true,
    ["y"] = true,
    ["ja"] = true,
    ["nein"] = true,
    ["x"] = true,
    ["y"] = true,
    ["ui"] = true,
    ["hp"] = true,
    ["id"] = true,
}

local function IsWordToken(word)
    return type(word) == "string" and word:match("^[a-z]+$") ~= nil
end

local function Tokenize(text)
    local out = {}
    for token in tostring(text or ""):gmatch("%S+") do
        out[#out + 1] = token
    end
    return out
end

local function IsAdjacentTranspose(a, b)
    local len = #a
    if len ~= #b or len < 3 then return false end
    local first
    for i = 1, len do
        if a:sub(i, i) ~= b:sub(i, i) then
            if first then
                return i == first + 1
                    and a:sub(first, first) == b:sub(i, i)
                    and a:sub(i, i) == b:sub(first, first)
                    and a:sub(i + 1) == b:sub(i + 1)
            end
            first = i
        end
    end
    return false
end

local function IsEditDistanceOne(a, b)
    local la, lb = #a, #b
    if math.abs(la - lb) > 1 then return false end
    if math.min(la, lb) < 5 then return false end
    if a:sub(1, 1) ~= b:sub(1, 1) then return false end

    if la == lb then
        local diff = 0
        for i = 1, la do
            if a:sub(i, i) ~= b:sub(i, i) then
                diff = diff + 1
                if diff > 1 then return false end
            end
        end
        return diff == 1
    end

    local shorter, longer = a, b
    if la > lb then shorter, longer = b, a end
    if longer == shorter .. "s" then return false end
    local i, j, skipped = 1, 1, false
    while i <= #shorter and j <= #longer do
        if shorter:sub(i, i) == longer:sub(j, j) then
            i = i + 1
            j = j + 1
        elseif skipped then
            return false
        else
            skipped = true
            j = j + 1
        end
    end
    return true
end

local function FuzzyWordMatch(word, expected)
    word = tostring(word or "")
    expected = tostring(expected or "")
    if word == expected then return true end
    if EXACT_ONLY_FUZZY_WORDS[word] or EXACT_ONLY_FUZZY_WORDS[expected] then return false end
    if not IsWordToken(word) or not IsWordToken(expected) then return false end
    if math.min(#word, #expected) < 3 then return false end
    if IsAdjacentTranspose(word, expected) then return true end
    return IsEditDistanceOne(word, expected)
end

local fuzzyPhraseCacheText
local fuzzyPhraseCache = {}
local fuzzyPhraseCacheTokens = {}
local fuzzyPhraseTokenCache = {}

local function FuzzyPhraseMatch(text, phrase)
    text = Normalize(text)
    phrase = Normalize(phrase)
    if text == "" or phrase == "" or #phrase < 3 then return false end
    if text ~= fuzzyPhraseCacheText then
        fuzzyPhraseCacheText = text
        fuzzyPhraseCache = {}
        fuzzyPhraseCacheTokens = Tokenize(text)
    elseif fuzzyPhraseCache[phrase] ~= nil then
        return fuzzyPhraseCache[phrase]
    end

    local phraseTokens = fuzzyPhraseTokenCache[phrase]
    if not phraseTokens then
        phraseTokens = Tokenize(phrase)
        fuzzyPhraseTokenCache[phrase] = phraseTokens
    end
    if #phraseTokens == 0 or #phraseTokens > 6 then
        fuzzyPhraseCache[phrase] = false
        return false
    end

    local textTokens = fuzzyPhraseCacheTokens
    local matched = false
    if #phraseTokens == 1 then
        for i = 1, #textTokens do
            if FuzzyWordMatch(textTokens[i], phraseTokens[1]) then
                matched = true
                break
            end
        end
    elseif #textTokens >= #phraseTokens then
        for start = 1, (#textTokens - #phraseTokens + 1) do
            local ok = true
            for offset = 1, #phraseTokens do
                if not FuzzyWordMatch(textTokens[start + offset - 1], phraseTokens[offset]) then
                    ok = false
                    break
                end
            end
            if ok then
                matched = true
                break
            end
        end
    end

    fuzzyPhraseCache[phrase] = matched
    return matched
end

A.FuzzyWordMatch = FuzzyWordMatch
A.FuzzyPhraseMatch = FuzzyPhraseMatch

local function HasPhrase(text, phrase)
    text = Normalize(text)
    phrase = Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function ContainsAny(text, words)
    for i = 1, #(words or {}) do
        if HasPhrase(text, words[i]) then return true end
    end
    return false
end

local UNIT_ORDER = { "targettarget", "focustarget", "player", "target", "focus", "pet", "boss" }
local GROUP_ORDER = { "mythicraid", "party", "raid" }
local ALL_UNITFRAMES = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local ALL_GROUPS = { "party", "raid", "mythicraid" }
local CLASS_POWER_TERMS = { "class power", "class resource", "class resources", "class bar", "resource bar" }
local GAMEPLAY_TERMS = { "gameplay", "combat timer", "combat state", "combat enter", "combat leave", "totem frame", "totemframe", "blizzard totem", "statue frame", "first dance", "combat crosshair", "crosshair", "fadenkreuz", "melee range spell" }
local GLOBAL_BARS_TERMS = { "bar texture", "bar background", "bar gradient", "gradient direction", "absorb bar", "absorb bars", "heal prediction", "heal absorb", "bar outline", "rounded frames", "rounded frame", "rounded texture", "highlight border", "aggro border", "dispel border", "purge border", "boss target border", "dispel overlay", "power text" }
local CASTBAR_ROOT_DETAIL_TERMS = {
    "castbar time", "cast time", "time text", "timer",
    "castbar icon", "cast icon", "spell icon",
    "castbar text", "castbar name", "castbar spell name", "spell name", "spell text",
    "interrupt", "interruptible", "kick", "kickable",
    "channel ticks", "channel tick lines", "castbar ticks", "tick lines",
    "glow", "spark", "sparks", "latency", "fill direction", "unified direction", "opposite direction",
    "texture", "background texture", "outline", "border thickness", "shake", "shake strength",
    "empower", "empowered", "stage blink", "spell name shortening", "max spell name length", "reserved spell name space",
    "focus kick", "focus interrupt", "interrupt ready",
}

local PAGE_TEXT_TARGETS = {
    { page = "home", label = "Dashboard", terms = { "dashboard", "home", "main menu", "start page", "overview" } },
    { page = "profiles", label = "Profiles", terms = { "profile", "profiles", "profil", "profile import", "profile export" } },
    { page = "gameplay", label = "Gameplay", terms = GAMEPLAY_TERMS },
    { page = "classpower", label = "Class Resources", terms = CLASS_POWER_TERMS },

    { page = "gf_indicators", label = "Group Indicators", terms = { "group indicators", "group indicator", "party indicators", "raid indicators", "group status icons", "raid status icons", "ready check", "summon icon", "role icon", "leader icon", "assist icon" } },
    { page = "gf_auras", label = "Group Auras", terms = { "group auras", "group aura", "party auras", "raid auras", "group buffs", "group debuffs", "party buffs", "raid debuffs" } },
    { page = "gf_bars", label = "Group Health & Text", terms = { "group health", "group text", "group bars", "party health", "party text", "party bars", "raid health", "raid text", "raid bars", "health and text" } },
    { page = "gf_layout", label = "Group Layout", terms = { "group layout", "party layout", "raid layout", "group settings", "party settings", "raid settings", "group frames", "groupframes", "party frames", "raid frames", "mythic raid", "mythicraid", "gruppenframes", "group", "party", "raid" } },

    { page = "auras3_filters", label = "Aura Filters", terms = { "aura filters", "aura filter", "filters", "blacklist", "aura blacklist", "blocked auras" } },
    { page = "auras3_styling", label = "Aura Style", terms = { "aura style", "aura styling", "aura colors", "aura cooldown text", "aura borders" } },
    { page = "auras3_debuffs", label = "Aura Debuffs", terms = { "debuff", "debuffs", "debuff settings", "debuff style" } },
    { page = "auras3_buffs", label = "Aura Buffs", terms = { "buff", "buffs", "buff settings", "buff style" } },
    { page = "auras3_styling", label = "Auras", terms = { "aura", "auras", "aura settings", "aura style" } },

    { page = "opt_castbar", label = "Castbars", terms = { "castbar", "castbars", "zauberleiste" } },
    { page = "opt_colors", label = "Colors", terms = { "colors", "colours", "color palette", "farben" } },
    { page = "opt_fonts", label = "Fonts", terms = { "fonts", "font", "schrift" } },
    { page = "opt_misc", label = "Miscellaneous", terms = { "misc", "miscellaneous", "tooltips", "tooltip", "modules style", "dropdown style" } },
    { page = "opt_bars", label = "Bars", terms = GLOBAL_BARS_TERMS },
    { page = "opt_bars", label = "Bars", terms = { "bars", "textures", "bar settings", "leisten" } },
    { page = "modules", label = "Modules", terms = { "modules", "advanced", "advanced modules", "module settings" } },

    { page = "uf_targettarget", label = "Target of Target", terms = { "targettarget", "target of target", "tot" } },
    { page = "uf_focustarget", label = "Focus Target", terms = { "focustarget", "focus target" } },
    { page = "uf_player", label = "Player", terms = { "player", "spieler" } },
    { page = "uf_target", label = "Target", terms = { "target", "ziel" } },
    { page = "uf_focus", label = "Focus", terms = { "focus", "fokus" } },
    { page = "uf_pet", label = "Pet", terms = { "pet", "begleiter" } },
    { page = "uf_boss", label = "Boss", terms = { "boss", "boss frames", "bossframes" } },
    { page = "search", label = "Search", terms = { "search page", "search results" } },
}

local function AddUnique(out, value)
    if not value then return end
    for i = 1, #out do
        if out[i] == value then return end
    end
    out[#out + 1] = value
end

local function DetectUnits(text)
    local units = {}
    if HasPhrase(text, "all unitframes") or HasPhrase(text, "all unitframe") or HasPhrase(text, "every unitframe") or HasPhrase(text, "alle unitframes") then
        for i = 1, #ALL_UNITFRAMES do AddUnique(units, ALL_UNITFRAMES[i]) end
        return units
    end
    local aliases = A.UnitAliases or {}
    for i = 1, #UNIT_ORDER do
        local unit = UNIT_ORDER[i]
        local list = aliases[unit] or {}
        for j = 1, #list do
            if HasPhrase(text, list[j]) then
                AddUnique(units, unit)
                break
            end
        end
    end
    if #units == 0 then
        if ContainsAny(text, { "player", "player frame", "player unitframe", "spieler", "self", "ich" }) then AddUnique(units, "player") end
        if ContainsAny(text, { "target", "target frame", "target unitframe", "ziel" }) then AddUnique(units, "target") end
        if ContainsAny(text, { "focus", "focus frame", "focus unitframe", "fokus" }) then AddUnique(units, "focus") end
        if ContainsAny(text, { "pet", "pet frame", "pet unitframe", "begleiter" }) then AddUnique(units, "pet") end
        if ContainsAny(text, { "boss", "boss frame", "boss frames", "bossframe", "bossframes" }) then AddUnique(units, "boss") end
        if ContainsAny(text, { "targettarget", "target of target", "target of target frame", "tot", "ziel des ziels" }) then AddUnique(units, "targettarget") end
        if ContainsAny(text, { "focustarget", "focus target", "focus target frame", "fokus ziel" }) then AddUnique(units, "focustarget") end
    end
    return units
end

local function DetectGroups(text)
    local groups = {}
    if HasPhrase(text, "all group frames") or HasPhrase(text, "all groups") or HasPhrase(text, "alle gruppenframes") then
        for i = 1, #ALL_GROUPS do AddUnique(groups, ALL_GROUPS[i]) end
        return groups
    end
    local mythicAliases = { "mythic raid frames", "mythic raid frame", "mythicraidframes", "mythicraidframe", "mythic raid", "mythicraid" }
    local scopeText = text
    if ContainsAny(scopeText, mythicAliases) then
        AddUnique(groups, "mythicraid")
        scopeText = " " .. Normalize(scopeText) .. " "
        for i = 1, #mythicAliases do
            local alias = Normalize(mythicAliases[i])
            if alias ~= "" then scopeText = scopeText:gsub(" " .. alias:gsub("([^%w%s])", "%%%1") .. " ", " ") end
        end
        scopeText = Normalize(scopeText)
    end
    if ContainsAny(scopeText, { "party", "party frame", "party frames", "partyframe", "partyframes" }) then AddUnique(groups, "party") end
    local raidScopeText = " " .. Normalize(scopeText) .. " "
    local raidDetailTerms = { "preserve raid groups", "raid marker icon", "raid marker indicator", "raid marker symbol", "raid marker", "raid markers" }
    for i = 1, #raidDetailTerms do
        local alias = raidDetailTerms[i]
        alias = Normalize(alias)
        if alias ~= "" then raidScopeText = raidScopeText:gsub(" " .. alias:gsub("([^%w%s])", "%%%1") .. " ", " ") end
    end
    raidScopeText = Normalize(raidScopeText)
    if ContainsAny(raidScopeText, { "raid", "raid frame", "raid frames", "raidframe", "raidframes", "schlachtzug" }) then AddUnique(groups, "raid") end
    if #groups == 0
        and not ContainsAny(text, { "group copy", "copy group", "copy category", "copy categories", "copy scope" })
        and ContainsAny(text, { "group frames", "group frame", "groups", "group", "gruppenframes", "gruppe", "gruppen" }) then
        for i = 1, #ALL_GROUPS do AddUnique(groups, ALL_GROUPS[i]) end
    end
    return groups
end

local function DetectGlobalScope(text)
    if HasPhrase(text, "all scopes") then return "shared" end
    if HasPhrase(text, "party") or HasPhrase(text, "party frames") or HasPhrase(text, "group frames") then return "gf_party" end
    if HasPhrase(text, "raid") or HasPhrase(text, "raid frames") or HasPhrase(text, "mythic raid") or HasPhrase(text, "mythicraid") then return "gf_raid" end
    local units = DetectUnits(text)
    if units[1] then return units[1] end
    if ContainsAny(text, { "shared", "global" }) then return "shared" end
    return nil
end

local OFF_WORDS = {
    "off", "disable", "disabled", "hide", "hidden", "false", "no",
    "dont", "dont show", "do not", "do not show", "never", "never show",
    "aus", "deaktivieren", "deaktiviert", "ausschalten", "ausgeschaltet",
    "verstecken", "versteckt", "ausblenden", "ausgeblendet", "nein",
}
local ON_WORDS = {
    "on", "enable", "enabled", "show", "visible", "true", "yes",
    "an", "aktivieren", "aktiviert", "einschalten", "eingeschaltet",
    "anzeigen", "einblenden", "eingeblendet", "sichtbar", "wieder an", "ja",
}

local function DetectBoolean(text)
    if ContainsAny(text, OFF_WORDS) then return false end
    if ContainsAny(text, ON_WORDS) then return true end
    return nil
end

local function FirstNumber(text)
    local value = text:match("[-+]?%d+%.?%d*")
    return tonumber(value)
end

function A._ExplicitNumberValue(text)
    text = tostring(text or "")
    local value
    for _, pattern in ipairs({
        "%f[%w]to%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]auf%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]zu%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]as%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]is%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]be%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]value%f[%W]%s+([-+]?%d+%.?%d*)",
        "=%s*([-+]?%d+%.?%d*)",
    }) do
        for numberText in text:gmatch(pattern) do
            value = tonumber(numberText)
        end
    end
    return value
end

function A._LastNumberValue(text)
    local value
    for numberText in tostring(text or ""):gmatch("[-+]?%d+%.?%d*") do
        value = tonumber(numberText)
    end
    return value
end

function A._NumberValueForText(setting, text)
    local explicit = A._ExplicitNumberValue(text)
    if explicit ~= nil then return explicit end
    local hay = setting and (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")) or ""
    if hay:find("%d") then return A._LastNumberValue(text) end
    return FirstNumber(text)
end

function A._RelativeNumberAmountForText(text)
    text = tostring(text or "")
    local value
    for _, pattern in ipairs({
        "%f[%w]by%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]um%f[%W]%s+([-+]?%d+%.?%d*)",
    }) do
        for numberText in text:gmatch(pattern) do
            value = tonumber(numberText)
        end
    end
    return value or FirstNumber(text)
end

local function Compact(text)
    return Normalize(text):gsub("%s+", "")
end

local pluralFoldCache = {}
local pluralFoldCacheCount = 0

local PLURAL_FOLD_KEEP = {
    this = true,
    was = true,
    yes = true,
    dps = true,
}

local function PluralFoldWord(word)
    word = tostring(word or "")
    if word == "" or word:match("^[-+]?%d") or PLURAL_FOLD_KEEP[word] then return word end
    local len = #word
    if len <= 3 then return word end
    if word:sub(-3) == "ies" and len > 4 then
        return word:sub(1, -4) .. "y"
    end
    if word:sub(-4) == "izes" and len > 4 then
        return word:sub(1, -2)
    end
    if word:sub(-2) == "es" then
        local base = word:sub(1, -3)
        if base:sub(-2) == "ss" or base:sub(-2) == "ch" or base:sub(-2) == "sh"
            or base:sub(-1) == "s" or base:sub(-1) == "x" or base:sub(-1) == "z" then
            return base
        end
    end
    if word:sub(-1) == "s" and word:sub(-2) ~= "ss" and word:sub(-2) ~= "us" then
        return word:sub(1, -2)
    end
    return word
end

local function PluralFoldText(text)
    text = Normalize(text)
    local cached = pluralFoldCache[text]
    if cached ~= nil then return cached end
    local out = {}
    for word in text:gmatch("%S+") do
        out[#out + 1] = PluralFoldWord(word)
    end
    local folded = table.concat(out, " ")
    if #text <= 180 then
        if pluralFoldCacheCount > 4096 then
            pluralFoldCache = {}
            pluralFoldCacheCount = 0
        end
        if pluralFoldCache[text] == nil then pluralFoldCacheCount = pluralFoldCacheCount + 1 end
        pluralFoldCache[text] = folded
    end
    return folded
end

local aliasRelationCacheText
local aliasRelationCacheValue
local function AliasRelationText(text)
    text = Normalize(text)
    if text == aliasRelationCacheText then return aliasRelationCacheValue end
    local padded = " " .. text .. " "
    if not (padded:find(" for ", 1, true) or padded:find(" on ", 1, true) or padded:find(" of ", 1, true)
        or padded:find(" vom ", 1, true) or padded:find(" von ", 1, true) or padded:find(" fuer ", 1, true) or padded:find(" für ", 1, true)) then
        aliasRelationCacheText = text
        aliasRelationCacheValue = text
        return text
    end
    local t = padded
    local rel = { "for", "on", "of", "vom", "von", "fuer", "für" }
    for i = 1, #rel do
        t = t:gsub("%f[%w]" .. rel[i] .. "%f[%W]", " ")
    end
    aliasRelationCacheText = text
    aliasRelationCacheValue = Trim(t:gsub("%s+", " "))
    return aliasRelationCacheValue
end

local function TextMatchesAlias(text, relationText, alias)
    if HasPhrase(text, alias) or HasPhrase(relationText or AliasRelationText(text), alias) then return true end
    local normalizedText = Normalize(text)
    local normalizedRelation = Normalize(relationText or AliasRelationText(text))
    local normalizedAlias = Normalize(alias)
    local foldedText = PluralFoldText(normalizedText)
    local foldedRelation = PluralFoldText(normalizedRelation)
    local foldedAlias = PluralFoldText(alias)
    if foldedText == normalizedText and foldedRelation == normalizedRelation and foldedAlias == normalizedAlias then return false end
    if HasPhrase(foldedText, foldedAlias) then return true end
    return HasPhrase(foldedRelation, foldedAlias)
end

local function ExtractColor(raw, text)
    local hex = tostring(raw or ""):match("#(%x%x%x%x%x%x)") or tostring(raw or ""):match("0x(%x%x%x%x%x%x)")
    if hex and A.HexToColor then
        return A.HexToColor(hex)
    end
    local rr, gg, bb = tostring(raw or ""):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if rr and gg and bb then
        local r, g, b = tonumber(rr) or 255, tonumber(gg) or 255, tonumber(bb) or 255
        if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
        return r, g, b, tostring(rr) .. "," .. tostring(gg) .. "," .. tostring(bb)
    end
    rr, gg, bb = tostring(text or ""):match("rgb%s+([-+]?%d+%.?%d*)%s+([-+]?%d+%.?%d*)%s+([-+]?%d+%.?%d*)")
    if not rr then
        rr, gg, bb = tostring(text or ""):match("r%s+([-+]?%d+%.?%d*)%s+g%s+([-+]?%d+%.?%d*)%s+b%s+([-+]?%d+%.?%d*)")
    end
    if rr and gg and bb then
        local r, g, b = tonumber(rr) or 1, tonumber(gg) or 1, tonumber(bb) or 1
        if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
        return r, g, b, tostring(rr) .. "," .. tostring(gg) .. "," .. tostring(bb)
    end
    if A.ColorFromName then
        for word in tostring(text or ""):gmatch("%S+") do
            local r, g, b, label = A.ColorFromName(word)
            if r then return r, g, b, label end
        end
    end
    return nil
end

local function DetectFrameType(text, ctx)
    if ContainsAny(text, { "alt mana", "alternative mana", "secondary mana", "dual resource mana" }) then return "altMana" end
    if ContainsAny(text, CLASS_POWER_TERMS) then return "classPower" end
    if ContainsAny(text, GLOBAL_BARS_TERMS) then return "globalBars" end
    if ContainsAny(text, { "combat timer" }) then return "combatTimer" end
    if ContainsAny(text, { "combat state", "combat enter", "combat leave", "combat enter leave" }) then return "combatState" end
    if ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame" }) then return "playerTotems" end
    if ContainsAny(text, { "first dance" }) then return "firstDance" end
    if ContainsAny(text, { "combat crosshair", "crosshair", "fadenkreuz", "melee range spell" }) then return "combatCrosshair" end
    if HasPhrase(text, "castbar") or HasPhrase(text, "zauberleiste") then return "castbar" end
    if ContainsAny(text, { "raid marker", "raidmarker", "raid marker icon", "raid marker indicator", "raid marker symbol", "target marker" })
        and not ContainsAny(text, { "group frame", "group frames", "party frame", "party frames", "raid frame", "raid frames", "mythic raid frame", "mythic raid frames" }) then
        return "unitframe"
    end
    if HasPhrase(text, "group frames") or HasPhrase(text, "gruppenframes") or HasPhrase(text, "party") or HasPhrase(text, "raid") then return "group" end
    if (HasPhrase(text, "it") or HasPhrase(text, "that") or HasPhrase(text, "das")) and ctx and type(ctx.lastFrameType) == "string" then
        return ctx.lastFrameType
    end
    return "unitframe"
end

local function DetectDirection(text, ctx)
    if ContainsAny(text, { "right", "rechts" }) then return "right" end
    if ContainsAny(text, { "left", "links" }) then return "left" end
    if ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" }) then return "down" end
    if ContainsAny(text, { "up", "higher", "hoeher", "hoch", "oben" }) then return "up" end
    if ContainsAny(text, { "more", "mehr", "weiter" }) and ctx and type(ctx.lastDirection) == "string" then
        return ctx.lastDirection
    end
    return nil
end

local function DetectAttribute(text, frameType)
    if ContainsAny(text, { "range fade", "range fading", "reichweite fade" }) then return "rangeFade" end
    if ContainsAny(text, { "raid marker", "raidmarker", "raid marker icon", "schlachtzug marker" }) then return "raidMarker" end
    if frameType == "castbar" and ContainsAny(text, { "castbar", "zauberleiste" }) then
        if ContainsAny(text, { "spell icon", "cast icon", "icon", "symbol" }) then return "icon" end
        if ContainsAny(text, { "cast time", "castbar time", "time text", "timer", "time" }) then return "time" end
        if ContainsAny(text, { "spell name", "spell text", "castbar name", "castbar text", "name text", "name", "text" }) then return "text" end
        if ContainsAny(text, { "interrupt", "interruptible", "kick", "kickable", "unterbrechen" }) then return "showInterrupt" end
    end
    if frameType == "castbar" and ContainsAny(text, { "castbar", "zauberleiste" }) and not ContainsAny(text, CASTBAR_ROOT_DETAIL_TERMS) and not ContainsAny(text, { "width", "height", "breite", "hoehe", "x", "y", "left", "right", "up", "down", "links", "rechts", "hoch", "tiefer" }) then
        return "enabled"
    end
    if ContainsAny(text, { "hp text", "health text", "health value", "life text", "leben text", "leben", "gesundheit", "lebenspunkte", "lebensanzeige" }) then return "hpText" end
    if ContainsAny(text, { "power text", "mana text", "power value", "mana value", "energie text", "energie", "ressource", "ressourcen" }) then return "powerText" end
    if ContainsAny(text, { "name text", "unit name", "name", "namen" }) then return "name" end
    if ContainsAny(text, { "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler" }) then return "width" end
    if ContainsAny(text, { "height", "tall", "taller", "shorter", "hoehe", "hoeher", "kleiner" }) then return "height" end
    if ContainsAny(text, { "enable", "disable", "show", "hide", "on", "off", "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden" })
        and ContainsAny(text, { "frame", "frames", "unitframe", "unitframes", "group", "gruppe" })
        and not ContainsAny(text, {
            "indicator", "indicators", "status icon", "status indicator", "icon", "icons", "symbol", "symbols",
            "border", "outline", "portrait", "alpha", "opacity", "texture", "font", "text", "name", "names", "color", "farbe",
            "power bar", "mana bar", "health bar", "hp bar", "castbar", "cast bar", "load condition",
            "offline", "solo", "sort", "sorting", "role", "scale", "scaling", "shorten", "shortening", "truncate", "truncation",
        }) then
        return "enabled"
    end
    return nil
end

local function PageForText(text)
    for i = 1, #PAGE_TEXT_TARGETS do
        local spec = PAGE_TEXT_TARGETS[i]
        if ContainsAny(text, spec.terms) then return spec.page, spec.label end
    end
    return nil, nil
end

local function FrameTypeForPage(page)
    if page == "profiles" then return "profiles" end
    if page == "opt_castbar" then return "castbar" end
    if page == "auras3" or page == "auras3_buffs" or page == "auras3_debuffs" or page == "auras3_rendering" or page == "auras3_styling" or page == "auras3_filters" then return "aura" end
    if page == "gf_layout" or page == "gf_auras" or page == "gf_indicators" then return "group" end
    if page == "opt_colors" then return "colors" end
    if page == "opt_fonts" then return "fonts" end
    if page == "opt_bars" then return "globalBars" end
    if page == "gameplay" then return "gameplay" end
    if page == "classpower" then return "classPower" end
    if type(page) == "string" and page:find("^uf_") then return "unitframe" end
    return nil
end

local function UnitPageKey(unit)
    if unit == "player" then return "uf_player" end
    if unit == "target" then return "uf_target" end
    if unit == "focus" then return "uf_focus" end
    if unit == "targettarget" then return "uf_targettarget" end
    if unit == "focustarget" then return "uf_focustarget" end
    if unit == "pet" then return "uf_pet" end
    if unit == "boss" then return "uf_boss" end
    return nil
end

P.Trim = Trim
P.Normalize = Normalize
P.FuzzyWordMatch = FuzzyWordMatch
P.FuzzyPhraseMatch = FuzzyPhraseMatch
P.HasPhrase = HasPhrase
P.ContainsAny = ContainsAny
P.UNIT_ORDER = UNIT_ORDER
P.GROUP_ORDER = GROUP_ORDER
P.ALL_UNITFRAMES = ALL_UNITFRAMES
P.ALL_GROUPS = ALL_GROUPS
P.CLASS_POWER_TERMS = CLASS_POWER_TERMS
P.GAMEPLAY_TERMS = GAMEPLAY_TERMS
P.GLOBAL_BARS_TERMS = GLOBAL_BARS_TERMS
P.CASTBAR_ROOT_DETAIL_TERMS = CASTBAR_ROOT_DETAIL_TERMS
P.PAGE_TEXT_TARGETS = PAGE_TEXT_TARGETS
P.AddUnique = AddUnique
P.DetectUnits = DetectUnits
P.DetectGroups = DetectGroups
P.DetectGlobalScope = DetectGlobalScope
P.OFF_WORDS = OFF_WORDS
P.ON_WORDS = ON_WORDS
P.DetectBoolean = DetectBoolean
P.FirstNumber = FirstNumber
P.Compact = Compact
P.AliasRelationText = AliasRelationText
P.TextMatchesAlias = TextMatchesAlias
P.PluralFoldWord = PluralFoldWord
P.PluralFoldText = PluralFoldText
P.ExtractColor = ExtractColor
P.DetectFrameType = DetectFrameType
P.DetectDirection = DetectDirection
P.DetectAttribute = DetectAttribute
P.PageForText = PageForText
P.FrameTypeForPage = FrameTypeForPage
P.UnitPageKey = UnitPageKey
