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

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    text = tostring(text or ""):lower()
    text = text:gsub("\195\131\194\164", "ae")
    text = text:gsub("\195\131\194\182", "oe")
    text = text:gsub("\195\131\194\188", "ue")
    text = text:gsub("\195\131\194\159", "ss")
    text = text:gsub("\195\164", "ae")
    text = text:gsub("\195\182", "oe")
    text = text:gsub("\195\188", "ue")
    text = text:gsub("\195\159", "ss")
    text = text:gsub("[\"'`]", "")
    text = text:gsub("[,;:!?%(%)]", " ")
    text = text:gsub("%s+", " ")
    text = Trim(text)
    text = text:gsub("target%s+of%s+target", "targettarget")
    text = text:gsub("target%s+target", "targettarget")
    text = text:gsub("focus%s+target", "focustarget")
    text = text:gsub("cast%s+bar", "castbar")
    text = text:gsub("castbars", "castbar")
    text = text:gsub("unit%s+frames", "unitframes")
    text = text:gsub("gruppen%s+frames", "gruppenframes")
    text = text:gsub("status%s+icons", "status icon")
    text = text:gsub("incoming%s+res%s+", "incoming rez ")
    text = text:gsub("incoming%s+res$", "incoming rez")
    return Trim(text)
end
A.Normalize = Normalize

local function HasPhrase(text, phrase)
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
    "glow", "spark", "latency", "fill direction", "unified direction", "opposite direction",
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
    { page = "auras3_debuffs", label = "Debuffs", terms = { "debuff", "debuffs", "debuff settings" } },
    { page = "auras3", label = "Buffs", terms = { "aura", "auras", "buff", "buffs", "buff settings" } },

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
    return units
end

local function DetectGroups(text)
    local groups = {}
    if HasPhrase(text, "all group frames") or HasPhrase(text, "all groups") or HasPhrase(text, "alle gruppenframes") then
        for i = 1, #ALL_GROUPS do AddUnique(groups, ALL_GROUPS[i]) end
        return groups
    end
    local aliases = A.UnitAliases or {}
    for i = 1, #GROUP_ORDER do
        local scope = GROUP_ORDER[i]
        local list = aliases[scope] or {}
        for j = 1, #list do
            if HasPhrase(text, list[j]) then
                AddUnique(groups, scope)
                break
            end
        end
    end
    if #groups == 0 and (HasPhrase(text, "group frames") or HasPhrase(text, "gruppenframes")) then
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
    "aus", "deaktivieren", "deaktiviert", "verstecken", "nein",
}
local ON_WORDS = {
    "on", "enable", "enabled", "show", "visible", "true", "yes",
    "an", "aktivieren", "aktiviert", "anzeigen", "wieder an", "ja",
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

local function Compact(text)
    return Normalize(text):gsub("%s+", "")
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
    return HasPhrase(text, alias) or HasPhrase(relationText or AliasRelationText(text), alias)
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
    if ContainsAny(text, { "hp text", "health text", "health value", "leben text" }) then return "hpText" end
    if ContainsAny(text, { "power text", "mana text", "power value", "mana value" }) then return "powerText" end
    if ContainsAny(text, { "name text", "unit name", "name", "namen" }) then return "name" end
    if ContainsAny(text, { "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler" }) then return "width" end
    if ContainsAny(text, { "height", "tall", "taller", "shorter", "hoehe", "hoeher", "kleiner" }) then return "height" end
    if ContainsAny(text, { "enable", "disable", "show", "hide", "on", "off", "an", "aus" })
        and ContainsAny(text, { "frame", "frames", "unitframe", "unitframes", "group", "gruppe" })
        and not ContainsAny(text, { "border", "outline", "portrait", "alpha", "opacity", "texture", "font", "text", "color", "farbe" }) then
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
    if page == "auras3" or page == "auras3_styling" or page == "auras3_filters" then return "aura" end
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

local COPY_SCOPE_DEFAULTS = {
    basics = true,
    text = true,
    portrait = true,
    power = true,
    castbar = true,
    status = true,
    load = true,
    transparency = true,
    layout = false,
}

local UNIT_COPY_SCOPE_SPECS = {
    { key = "layout", aliases = { "layout", "position", "size", "anchoring", "anchor", "width", "height" } },
    { key = "text", aliases = { "text", "name", "hp", "health text", "hp text", "power text", "font", "fonts" } },
    { key = "portrait", aliases = { "portrait", "portrait settings" } },
    { key = "power", aliases = { "power bar", "powerbar", "detached power", "detached power bar", "resource bar" } },
    { key = "castbar", aliases = { "castbar", "cast bar" } },
    { key = "status", aliases = { "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators", "level indicator", "raid marker" } },
    { key = "load", aliases = { "load condition", "load conditions", "hide mounted", "hide out of combat" } },
    { key = "transparency", aliases = { "transparency", "opacity", "alpha", "range fade" } },
    { key = "basics", aliases = { "frame basics", "basic settings", "basics", "enable state", "smooth fill", "reverse fill" } },
}

local GROUP_COPY_SCOPE_DEFAULTS = {
    general = true,
    health = true,
    text = true,
    font = true,
    border = true,
    range = true,
    indicators = true,
    auras = true,
    highlight = true,
    dstripe = true,
    features = true,
}

local GROUP_COPY_SCOPE_SPECS = {
    { key = "general", aliases = { "general", "basics", "basic settings", "layout", "size", "width", "height", "spacing", "growth", "sort", "sorting", "columns", "raid groups" } },
    { key = "health", aliases = { "health", "health bars", "bars", "power", "power bar", "power text", "bar texture", "dispel overlay" } },
    { key = "text", aliases = { "text", "name", "health text", "hp text", "text and name" } },
    { key = "font", aliases = { "font", "fonts", "font override", "font color", "font outline" } },
    { key = "border", aliases = { "background", "opacity", "alpha", "transparency", "background opacity" } },
    { key = "range", aliases = { "range", "range fade", "offline alpha" } },
    { key = "indicators", aliases = { "indicators", "status icons", "status icon", "role icon", "leader icon", "assist icon", "raid marker", "ready check", "summon icon" } },
    { key = "auras", aliases = { "auras", "aura", "buffs", "buff", "debuffs", "debuff" } },
    { key = "highlight", aliases = { "highlight", "aggro", "aggro highlight", "dispel border", "purge border" } },
    { key = "dstripe", aliases = { "debuff stripe", "stripe" } },
    { key = "features", aliases = { "corner", "corner indicator", "corner indicators", "corner dots", "spell indicator", "spell indicators", "corner spell" } },
}

local function CopyScopeDefaults()
    local UP = M and M.UnitPage
    if UP and type(UP.NewCopyScopeDefaults) == "function" then
        local scopes = UP.NewCopyScopeDefaults()
        if type(scopes) == "table" then return scopes end
    end

    local scopes = {}
    local cats = UP and type(UP.UF_COPY_CATEGORIES) == "table" and UP.UF_COPY_CATEGORIES or nil
    if cats then
        for i = 1, #cats do
            local cat = cats[i]
            if type(cat) == "table" and type(cat.key) == "string" then
                scopes[cat.key] = cat.default ~= false
            end
        end
        if next(scopes) then return scopes end
    end

    for key, value in pairs(COPY_SCOPE_DEFAULTS) do scopes[key] = value end
    return scopes
end

local function CopyScopeMatches(text, specs)
    local matches = {}
    local seen = {}
    for i = 1, #(specs or {}) do
        local spec = specs[i]
        if spec.key and not seen[spec.key] and ContainsAny(text, spec.aliases) then
            matches[#matches + 1] = spec.key
            seen[spec.key] = true
        end
    end
    return matches
end

local function ApplyCopyScopeMatches(scopes, matches)
    if not matches or #matches == 0 then return false end
    for key in pairs(scopes) do scopes[key] = false end
    for i = 1, #matches do scopes[matches[i]] = true end
    return true
end

local function CopyScopesForText(text)
    local scopes = CopyScopeDefaults()
    if ContainsAny(text, { "all settings", "all categories", "everything", "complete settings", "entire unit", "whole unit" }) then
        for key in pairs(scopes) do scopes[key] = true end
    else
        local matched = ApplyCopyScopeMatches(scopes, CopyScopeMatches(text, UNIT_COPY_SCOPE_SPECS))
        if matched and ContainsAny(text, { "size", "width", "height" }) then scopes.basics = true end
    end
    return scopes
end

local function GroupCopyScopeDefaults()
    local GP = M and M.GroupPage
    if GP and type(GP.NewGFCopyScopes) == "function" then
        local scopes = GP.NewGFCopyScopes()
        if type(scopes) == "table" then return scopes end
    end

    local scopes = {}
    local cats = GP and type(GP.GF_COPY_CATEGORIES) == "table" and GP.GF_COPY_CATEGORIES or nil
    if cats then
        for i = 1, #cats do
            local cat = cats[i]
            if type(cat) == "table" and type(cat.key) == "string" then scopes[cat.key] = true end
        end
        if next(scopes) then return scopes end
    end

    for key, value in pairs(GROUP_COPY_SCOPE_DEFAULTS) do scopes[key] = value end
    return scopes
end

local function GroupCopyScopesForText(text)
    local scopes = GroupCopyScopeDefaults()
    if ContainsAny(text, { "all settings", "all categories", "everything", "complete settings", "entire group", "whole group" }) then
        for key in pairs(scopes) do scopes[key] = true end
    else
        ApplyCopyScopeMatches(scopes, CopyScopeMatches(text, GROUP_COPY_SCOPE_SPECS))
    end
    return scopes
end

local function CleanProfileName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("^profile%s+", "")
    name = name:gsub("%s+profile$", "")
    name = name:gsub("^named%s+", "")
    name = name:gsub("^called%s+", "")
    name = name:gsub("^to%s+", "")
    name = name:gsub("^as%s+", "")
    name = Trim(name)
    if name == "" then return nil end
    return name
end

local function RawAfterPrefix(raw, prefixes)
    raw = tostring(raw or "")
    local lower = raw:lower()
    for i = 1, #(prefixes or {}) do
        local prefix = prefixes[i]
        if lower:sub(1, #prefix) == prefix then
            return CleanProfileName(raw:sub(#prefix + 1))
        end
    end
    return nil
end

local function RawBetween(raw, prefix, suffix)
    raw = tostring(raw or "")
    local lower = raw:lower()
    if lower:sub(1, #prefix) == prefix and lower:sub(-#suffix) == suffix then
        return CleanProfileName(raw:sub(#prefix + 1, #raw - #suffix))
    end
    return nil
end

local function RawCreateProfileName(raw)
    return RawAfterPrefix(raw, { "create profile ", "new profile " })
        or RawBetween(raw, "create ", " profile")
        or RawBetween(raw, "new ", " profile")
end

local function RawCopyProfileName(raw)
    return RawAfterPrefix(raw, { "copy current profile to ", "copy profile to ", "copy profile ", "duplicate profile " })
        or RawBetween(raw, "duplicate ", " profile")
end

local function RawRenameProfileNames(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local function splitAfterPrefix(prefix)
        if lower:sub(1, #prefix) ~= prefix then return nil, nil end
        local start = #prefix + 1
        local sepStart, sepEnd = lower:find("%s+to%s+", start)
        if not sepStart then return nil, nil end
        return CleanProfileName(raw:sub(start, sepStart - 1)), CleanProfileName(raw:sub(sepEnd + 1))
    end

    local source, dest = splitAfterPrefix("rename profile ")
    if source and dest then return source, dest end

    dest = RawAfterPrefix(raw, { "rename current profile to ", "rename profile to " })
    if dest then return nil, dest end

    source, dest = splitAfterPrefix("rename ")
    if source and dest then
        source = CleanProfileName((source:gsub("%s+profile$", "")))
        return source, dest
    end

    return nil, nil
end

local PROFILE_EXPORT_KIND_LABELS = {
    all = "Full profile",
    unitframe = "Unitframes",
    castbar = "Castbars",
    colors = "Colors",
    gameplay = "Gameplay",
    groupframe = "Group Frames",
}

local function ProfileExportKindForText(text)
    if ContainsAny(text, { "colors", "color palette", "color settings" }) then return "colors" end
    if ContainsAny(text, { "castbar", "castbars" }) then return "castbar" end
    if ContainsAny(text, { "gameplay", "combat timer", "crosshair", "totem frame" }) then return "gameplay" end
    if ContainsAny(text, { "group frame", "group frames", "groupframe", "party", "raid", "mythicraid" }) then return "groupframe" end
    if ContainsAny(text, { "unitframe", "unitframes", "unit frame", "unit frames", "player", "target", "focus", "boss", "pet" }) then return "unitframe" end
    return "all"
end

local function RawAfterLastConnector(raw, connectors)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local bestEnd
    for i = 1, #(connectors or {}) do
        local connector = connectors[i]
        local start = 1
        while true do
            local s, e = lower:find(connector, start, true)
            if not s then break end
            if not bestEnd or e > bestEnd then bestEnd = e end
            start = e + 1
        end
    end
    if not bestEnd then return nil end
    local value = Trim(raw:sub(bestEnd + 1))
    if value == "" then return nil end
    return value
end

local function CleanSpecName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("^spec%s+", "")
    name = name:gsub("^specialization%s+", "")
    name = name:gsub("%s+spec$", "")
    name = name:gsub("%s+specialization$", "")
    name = name:gsub("^for%s+", "")
    name = name:gsub("^to%s+", "")
    name = Trim(name)
    if name == "" then return nil end
    return name
end

local function ImportNewProfileName(raw, endIndex, text)
    local after = Trim(tostring(raw or ""):sub((endIndex or 0) + 1))
    local lower = after:lower()
    if lower:sub(1, 3) == "as " then return CleanProfileName(after:sub(4)) end
    if lower:sub(1, 15) == "to new profile " then return CleanProfileName(after:sub(16)) end
    if lower:sub(1, 12) == "new profile " then return CleanProfileName(after:sub(13)) end
    local name = text:match("as%s+(.+)$")
        or text:match("to%s+new%s+profile%s+(.+)$")
        or text:match("new%s+profile%s+(.+)$")
    return CleanProfileName(name)
end

local function BuildSpecAutoSwitch(text)
    if not ContainsAny(text, {
        "auto switch profile", "auto-switch profile", "profile auto switch",
        "profile by specialization", "profile by spec", "spec profile switching",
        "specialization profile switching",
    }) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local setting = Registry and Registry:GetSetting("profiles.specAutoSwitch")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = (value and "Enable" or "Disable") .. " spec profile switching",
        summary = "Uses the MSUF Profiles spec auto-switch setting.",
    } or nil
end

local function BuildSpecProfileAction(text)
    if not (ContainsAny(text, { "spec profile", "specialization profile", "profile by spec", "profile by specialization" })
        or (HasPhrase(text, "profile") and (HasPhrase(text, "spec") or HasPhrase(text, "specialization"))))
    then
        return nil
    end
    if ContainsAny(text, { "clear", "remove", "unset" }) then
        local spec = text:match("clear%s+spec%s+profile%s+(.+)$")
            or text:match("clear%s+(.+)%s+spec%s+profile$")
            or text:match("remove%s+spec%s+profile%s+(.+)$")
            or text:match("unset%s+spec%s+profile%s+(.+)$")
            or text:match("remove%s+profile%s+from%s+(.+)%s+spec$")
        spec = CleanSpecName(spec)
        local action = Registry and Registry:GetAction("clear_spec_profile")
        return spec and action and {
            kind = "action",
            action = action,
            args = { spec = spec },
            label = "Clear spec profile",
            summary = "Clears the selected specialization profile assignment.",
        } or nil
    end
    if ContainsAny(text, { "assign", "set" }) then
        local spec, name = text:match("set%s+spec%s+profile%s+(.+)%s+to%s+(.+)$")
        if not spec then spec, name = text:match("set%s+(.+)%s+spec%s+profile%s+to%s+(.+)$") end
        if not spec then name, spec = text:match("assign%s+(.+)%s+profile%s+to%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("assign%s+profile%s+(.+)%s+to%s+spec%s+(.+)$") end
        if not spec then name, spec = text:match("assign%s+(.+)%s+to%s+(.+)%s+spec%s+profile$") end
        spec = CleanSpecName(spec)
        name = CleanProfileName(name)
        local action = Registry and Registry:GetAction("set_spec_profile")
        return spec and name and action and {
            kind = "action",
            action = action,
            args = { spec = spec, name = name },
            label = "Set spec profile",
            summary = "Assigns an existing profile to a specialization.",
        } or nil
    end
    return nil
end


local function ParseWorkflowLifecycle(text)
    if ContainsAny(text, { "workflow status", "assistant workflow status", "pending workflow", "pending flow", "active workflow", "what workflow", "what is pending" }) then
        local action = Registry and Registry:GetAction("assistant.workflow.status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant workflow status",
            summary = "Shows pending confirmations, panels, flows, and Edit Mode lifecycle status.",
        } or nil
    end
    if text == "back" or ContainsAny(text, { "go back", "open previous page", "previous page", "return to previous page", "back to previous page" }) then
        local action = Registry and Registry:GetAction("dashboard_page_back")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open previous Dashboard page",
            summary = "Uses the Assistant page stack when available.",
        } or nil
    end
    if text == "cancel" or ContainsAny(text, { "cancel workflow", "cancel current workflow", "cancel assistant workflow", "stop assistant workflow", "abort workflow" }) then
        local action = Registry and Registry:GetAction("assistant.workflow.cancel")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Cancel active Assistant workflow",
            summary = "Cancels the active Assistant confirmation, flow, panel, or guide when available.",
        } or nil
    end
    if ContainsAny(text, { "close import", "cancel import", "close export", "close assistant panel", "close profile import", "cancel profile import", "close profile export" }) then
        local action = Registry and Registry:GetAction("assistant.panel.close")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Close Assistant panel",
            summary = "Closes the current Assistant import/export/text panel.",
        } or nil
    end
    return nil
end

local function BuildMenuSelectorState(args, label, summary)
    local action = Registry and Registry:GetAction("set_menu_selector_state")
    return action and {
        kind = "action",
        action = action,
        args = args,
        label = label or "Set menu selector state",
        summary = summary or "Selects or stages a Menu2 UI state.",
    } or nil
end

local function ParseProfileStagingState(text, raw)
    if not ContainsAny(text, { "profile", "profiles", "profil" }) then return nil end
    local hasStagingIntent = ContainsAny(text, {
        "field", "input", "text box", "textbox", "staging", "stage", "select", "choose", "set", "fill", "paste into",
        "turn on", "turn off", "enable", "disable",
    })
    if not hasStagingIntent then return nil end

    if ContainsAny(text, { "export kind", "export type", "export dropdown", "profile export kind", "profile export type" }) then
        return BuildMenuSelectorState({
            selector = "profile_staging",
            field = "profileExportKind",
            kind = ProfileExportKindForText(text),
        }, "Select profile export kind", "Selects the Profiles export-kind dropdown without immediately exporting.")
    end

    if ContainsAny(text, { "import and create new profile", "import create new", "new profile import", "new-profile import", "import into new profile", "create new profile import" }) then
        local value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, { "off", "disable", "disabled", "current profile", "active profile" }) end
        return BuildMenuSelectorState({
            selector = "profile_staging",
            field = "profileImportCreateNew",
            value = value,
        }, "Set profile import mode", "Sets the Profiles import-and-create-new-profile toggle.")
    end

    if ContainsAny(text, { "new profile name", "new-profile name", "import new profile name", "import profile name" })
        and ContainsAny(text, { "import", "new profile", "new-profile" })
    then
        local value = CleanProfileName(RawAfterLastConnector(raw, { " to ", " as ", " named ", " called ", " name ", " value " }))
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileImportNewName",
                value = value,
            }, "Set profile import new-profile name", "Stages the Profiles new-profile import name field.")
        end
    end

    if ContainsAny(text, { "profile string", "import string", "profile import string" })
        and ContainsAny(text, { "field", "input", "text box", "textbox", "stage", "staging", "set", "fill", "paste into" })
    then
        local value = RawAfterLastConnector(raw, { " to ", " with ", " value ", " text ", " string ", " paste " })
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileString",
                value = value,
            }, "Set profile string field", "Stages the Profiles profile-string field without importing.")
        end
    end

    if ContainsAny(text, { "profile name field", "profile name input", "create copy name", "create/copy name", "profile create name", "profile copy name", "profile name for create", "profile name for copy" }) then
        local value = CleanProfileName(RawAfterLastConnector(raw, { " to ", " as ", " named ", " called ", " name ", " value " }))
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileCreateCopyName",
                value = value,
            }, "Set profile create/copy name", "Stages the Profiles create/copy name field.")
        end
    end

    return nil
end

local function ParseGroupCopyScopeState(text)
    if not ContainsAny(text, { "group copy", "group frame copy", "group frames copy", "copy category", "copy categories", "copy scope", "copy scopes" }) then return nil end
    if not ContainsAny(text, { "category", "categories", "scope", "scopes" }) then return nil end

    if ContainsAny(text, { "all categories", "select all", "turn on all", "enable all" })
        or (ContainsAny(text, { "all" }) and ContainsAny(text, { "turn on", "enable", "select" }))
    then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "all",
        }, "Select all group copy categories", "Sets every Group Frames copy-popup category checkbox on.")
    end
    if ContainsAny(text, { "no categories", "none", "select none", "clear categories", "turn off all", "disable all" })
        or (ContainsAny(text, { "clear", "disable" }) and ContainsAny(text, { "category", "categories", "scope", "scopes" }))
    then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "none",
        }, "Clear group copy categories", "Sets every Group Frames copy-popup category checkbox off.")
    end

    local matches = CopyScopeMatches(text, GROUP_COPY_SCOPE_SPECS)
    if #matches == 0 then return nil end
    if ContainsAny(text, { "only", "only these", "just" }) then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "only",
            categories = matches,
        }, "Select only group copy categories", "Sets the Group Frames copy-popup categories to exactly the requested category set.")
    end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, { "exclude", "without", "remove", "disable" }) then value = false else value = true end
    end
    return BuildMenuSelectorState({
        selector = "group_copy_scope",
        category = matches[1],
        value = value,
    }, "Set group copy category", "Sets one Group Frames copy-popup category checkbox.")
end

local function ParseProfile(text, raw)
    local rawText = tostring(raw or "")
    local startIndex, endIndex, compact = rawText:find("(MSUF%d+:%S+)")
    local hasProfile = ContainsAny(text, { "profile", "profiles", "profil" })
    local rawLower = tostring(raw or ""):lower()
    if compact and (hasProfile or ContainsAny(text, { "import", "importiere", "paste" }) or rawLower:find("^msuf%d+:")) then
        local legacy = ContainsAny(text, { "legacy import", "import legacy", "old profile import", "legacy profile" })
        local newName = ImportNewProfileName(rawText, endIndex, text)
        local action = Registry and Registry:GetAction(legacy and "import_legacy_profile_string" or (newName and "import_profile_string_new" or "import_profile_string"))
        return action and {
            kind = "action",
            action = action,
            args = newName and { value = compact, name = newName } or { value = compact },
            confirmRequired = true,
            label = legacy and "Import legacy profile string" or (newName and ("Import profile string as " .. tostring(newName)) or "Import profile string"),
            summary = newName and "Imports profile data into a new profile." or "Imports profile data into the active profile.",
        } or nil
    end
    if not hasProfile then return nil end

    local specSwitch = BuildSpecAutoSwitch(text)
    if specSwitch then return specSwitch end

    local specProfile = BuildSpecProfileAction(text)
    if specProfile then return specProfile end

    if ContainsAny(text, { "wago profile", "wago profiles", "browse wago profiles", "profile hub" }) then
        local action = Registry and Registry:GetAction("copy_wago_profiles_link")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Copy Wago profiles link",
            summary = "Opens a copyable Wago MSUF profiles link.",
        } or nil
    end

    if ContainsAny(text, { "export", "backup", "copy string", "exportieren" }) then
        local kind = ProfileExportKindForText(text)
        local action = Registry and Registry:GetAction("export_profile")
        return action and {
            kind = "action",
            action = action,
            args = { kind = kind },
            label = "Export current profile",
            summary = "Creates a copyable profile export string.",
        } or nil
    end

    if ContainsAny(text, { "import", "importieren", "paste" }) then
        local action = Registry and Registry:GetAction("open_profile_import")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open profile import",
            summary = "Opens the Profiles import UI.",
        } or nil
    end

    if ContainsAny(text, { "delete", "remove", "loeschen", "profil loeschen" }) then
        local name = text:match("delete%s+profile%s+(.+)$")
            or text:match("delete%s+(.+)%s+profile$")
            or text:match("remove%s+profile%s+(.+)$")
            or text:match("remove%s+(.+)%s+profile$")
            or text:match("loesche%s+profil%s+(.+)$")
            or text:match("profil%s+(.+)%s+loeschen$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("delete_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                confirmRequired = true,
                label = "Delete profile " .. tostring(name),
                summary = "Deletes an MSUF profile through the existing profile helper.",
            } or nil
        end
    end

    if ContainsAny(text, { "switch", "wechsel", "change profile" }) then
        local name = text:match("switch%s+to%s+(.+)$")
            or text:match("switch%s+profile%s+to%s+(.+)$")
            or text:match("wechsel%s+zu%s+(.+)$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("switch_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                label = "Switch profile",
                summary = "Switches the active MSUF profile.",
            } or nil
        end
    end

    if ContainsAny(text, { "create", "new profile", "erstellen" }) then
        local name = RawCreateProfileName(rawText)
            or text:match("create%s+profile%s+(.+)$")
            or text:match("create%s+(.+)%s+profile$")
            or text:match("new%s+profile%s+(.+)$")
            or text:match("new%s+(.+)%s+profile$")
            or text:match("profile%s+(.+)$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("create_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name, switch = true },
                label = "Create profile",
                summary = "Creates a new MSUF profile and switches to it.",
            } or nil
        end
    end

    if ContainsAny(text, { "rename", "umbenennen", "profile rename" }) then
        local source, dest = RawRenameProfileNames(rawText)
        if not source and not dest then source, dest = text:match("rename%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("rename%s+(.+)%s+profile%s+to%s+(.+)$") end
        if not source then source, dest = text:match("rename%s+(.+)%s+to%s+(.+)$") end
        if not source then dest = text:match("rename%s+current%s+profile%s+to%s+(.+)$") or text:match("rename%s+profile%s+to%s+(.+)$") end
        source = CleanProfileName(source)
        dest = CleanProfileName(dest)
        if dest then
            local action = Registry and Registry:GetAction("rename_profile")
            return action and {
                kind = "action",
                action = action,
                args = { source = source, name = dest },
                confirmRequired = true,
                label = "Rename profile",
                summary = "Renames a profile through a shared helper if one exists.",
            } or nil
        end
        if source then
            local action = Registry and Registry:GetAction("start_profile_rename_flow")
            return action and {
                kind = "action",
                action = action,
                args = { source = source },
                label = "Start profile rename flow",
                summary = "Asks for the missing destination profile name.",
            } or nil
        end
    end

    if ContainsAny(text, { "copy", "duplicate", "duplizieren" }) then
        local source, dest = text:match("copy%s+profile%s+(.+)%s+to%s+(.+)$")
        if not source then source, dest = text:match("copy%s+(.+)%s+profile%s+to%s+(.+)$") end
        source = CleanProfileName(source)
        dest = CleanProfileName(dest)
        if source and dest then
            local action = Registry and Registry:GetAction("copy_profile_from_to")
            return action and {
                kind = "action",
                action = action,
                args = { source = source, name = dest },
                confirmRequired = true,
                label = "Copy profile " .. tostring(source) .. " to " .. tostring(dest),
                summary = "Copies a named source profile to a destination profile.",
            } or nil
        end

        local name = RawCopyProfileName(rawText)
            or text:match("copy%s+current%s+profile%s+to%s+(.+)$")
            or text:match("copy%s+profile%s+to%s+(.+)$")
            or text:match("copy%s+profile%s+(.+)$")
            or text:match("duplicate%s+profile%s+(.+)$")
            or text:match("duplicate%s+(.+)%s+profile$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("copy_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                confirmRequired = true,
                label = "Copy current profile",
                summary = "Copies the active profile to a new profile name.",
            } or nil
        end

        local sourceOnly = RawAfterPrefix(rawText, {
                "copy from profile ",
                "copy existing profile ",
                "copy source profile ",
            })
            or text:match("^copy%s+from%s+profile%s+(.+)$")
            or text:match("^copy%s+existing%s+profile%s+(.+)$")
            or text:match("^copy%s+source%s+profile%s+(.+)$")
        sourceOnly = CleanProfileName(sourceOnly)
        if sourceOnly and not text:match("%s+to%s+") then
            local action = Registry and Registry:GetAction("start_profile_copy_flow")
            return action and {
                kind = "action",
                action = action,
                args = { source = sourceOnly },
                label = "Start profile copy flow",
                summary = "Asks for the missing destination profile name.",
            } or nil
        end
    end

    if ContainsAny(text, {
        "list profiles", "show profiles", "profile list", "profile summary",
        "profile status", "current profile", "active profile", "which profile",
        "spec profiles", "specialization profiles",
    }) and not ContainsAny(text, {
        "reset", "delete", "remove", "switch", "wechsel", "copy", "duplicate",
        "create", "new profile", "import", "export", "backup",
    }) then
        local action = Registry and Registry:GetAction("profile_summary")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show profile summary",
            summary = "Shows current profile status and spec profile mappings.",
        } or nil
    end
    return nil
end

local AURA_BLACKLIST_PRESETS = {
    { key = "RAID_BUFFS", aliases = { "raid buffs", "long term raid buffs", "raid buff preset" } },
    { key = "PRESERVATION_EVOKER", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", aliases = { "self buffs", "long term self buffs" } },
    { key = "ROGUE_POISONS", aliases = { "rogue poisons", "poisons" } },
    { key = "SHAMAN_IMBUE", aliases = { "shaman imbues", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", aliases = { "resource auras", "resource buffs" } },
    { key = "COOLDOWNS", aliases = { "cooldowns", "cooldown auras" } },
}

local function AuraBlacklistScope(text)
    if ContainsAny(text, { "shared", "global", "all auras", "all aura" }) then return "shared" end
    local units = DetectUnits(text)
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    end
    return "shared"
end

local AURA_QUICK_PRESETS = {
    { key = "clean", aliases = { "clean", "clean 6 12", "clean aura", "clean auras" } },
    { key = "focused", aliases = { "focused", "focused 10 16", "focused aura", "focused auras" } },
    { key = "performance", aliases = { "fast", "performance", "fast 4 8", "performance aura", "performance auras" } },
}

local function AuraQuickPresetForText(text)
    for i = 1, #AURA_QUICK_PRESETS do
        local preset = AURA_QUICK_PRESETS[i]
        if ContainsAny(text, preset.aliases) then return preset.key end
    end
    return nil
end

local function ParseAuraQuickPreset(text)
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if not ContainsAny(text, { "preset", "quick setup", "quicksetup", "setup", "apply", "use" }) then return nil end
    local preset = AuraQuickPresetForText(text)
    if not preset then return nil end
    local action = Registry and Registry:GetAction("apply_aura_quick_preset")
    return action and {
        kind = "action",
        action = action,
        args = { scope = AuraBlacklistScope(text), preset = preset },
        confirmRequired = true,
        label = "Apply aura quick preset",
        summary = "Applies the shared Auras quick setup helper.",
    } or nil
end

local function AuraBlacklistPresetForText(text)
    for i = 1, #AURA_BLACKLIST_PRESETS do
        local spec = AURA_BLACKLIST_PRESETS[i]
        if ContainsAny(text, spec.aliases) then return spec.key end
    end
    return nil
end

local function AuraGroupBlacklistScope(text)
    if ContainsAny(text, { "party", "party frames", "gruppe" }) then return "party" end
    if ContainsAny(text, { "raid", "raid frames", "mythic raid", "mythicraid", "schlachtzug" }) then return "raid" end
    if ContainsAny(text, { "group frames", "gruppenframes", "all groups" }) then return "raid" end
    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" then return "party" end
    end
    for i = 1, #groups do
        if groups[i] == "raid" or groups[i] == "mythicraid" then return "raid" end
    end
    return "raid"
end

local function AuraGroupBlacklistLane(text)
    if ContainsAny(text, { "debuff", "debuffs" }) then return "debuff" end
    return "buff"
end

local function AuraGroupBlacklistCategoryForText(text)
    if A.ResolveAuraGroupCategory then
        local resolved = A.ResolveAuraGroupCategory(text)
        if resolved then return resolved end
    end
    return AuraBlacklistPresetForText(text)
end

local function ParseAuraGroupCategoryBlacklist(text)
    local categoryIntent = ContainsAny(text, {
        "category", "categories", "public category", "public categories",
        "category blacklist", "category blacklists", "blacklisted category", "blacklisted categories",
    })
    if not categoryIntent then return nil end
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "group", "party", "raid", "mythic raid", "mythicraid" }) then return nil end

    local category = AuraGroupBlacklistCategoryForText(text)
    local summaryIntent = ContainsAny(text, { "list", "summary", "current", "what is", "whats" })
        or (ContainsAny(text, { "show" }) and ContainsAny(text, { "blacklist", "category blacklist", "blacklisted category", "blacklisted categories" }))
    if summaryIntent then
        local action = Registry and Registry:GetAction("aura_group_category_blacklist_summary")
        return action and {
            kind = "action",
            action = action,
            args = { scope = AuraGroupBlacklistScope(text), lane = AuraGroupBlacklistLane(text) },
            label = "Show group aura category blacklist",
            summary = "Shows the public aura category blacklist for group-frame auras.",
        } or nil
    end

    if not category then return nil end
    local value
    if ContainsAny(text, { "allow", "unblacklist", "remove", "clear", "include", "show", "anzeigen", "entfernen", "loeschen" }) then
        value = false
    elseif ContainsAny(text, { "blacklist", "hide", "block", "exclude", "disable", "ausblenden", "verstecken", "deaktivieren" }) then
        value = true
    end
    if value == nil then return nil end

    local action = Registry and Registry:GetAction("aura_group_category_blacklist_set")
    return action and {
        kind = "action",
        action = action,
        args = {
            scope = AuraGroupBlacklistScope(text),
            lane = AuraGroupBlacklistLane(text),
            category = category,
            value = value,
        },
        label = "Set group aura category blacklist",
        summary = "Edits the group-frame public aura category blacklist through the Auras3 MenuModel.",
    } or nil
end

local function AuraBlacklistSpellValue(raw)
    raw = tostring(raw or "")
    local value = raw:match("(spell:%d+)") or raw:match("#%s*(%d+)") or raw:match("(%d%d+)")
    if value then return value end
    value = raw:match("[Aa]dd%s+(.+)%s+to%s+.+[Bb]lacklist")
        or raw:match("[Bb]lacklist%s+(.+)%s+for%s+")
        or raw:match("[Rr]emove%s+(.+)%s+from%s+.+[Bb]lacklist")
    value = CleanProfileName(value)
    if value and value ~= "" then return value end
    return nil
end

local function ParseAuraBlacklist(text, raw)
    if not ContainsAny(text, { "blacklist", "blocked aura", "blocked auras", "ignore aura", "ignore auras" }) then return nil end
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "spell" }) then return nil end

    local scope = AuraBlacklistScope(text)
    if ContainsAny(text, { "show", "list", "summary", "current", "what is", "whats" }) then
        local action = Registry and Registry:GetAction("aura_blacklist_summary")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope },
            label = "Show aura blacklist",
            summary = "Shows the prepared aura blacklist for the selected scope.",
        } or nil
    end

    local preset = AuraBlacklistPresetForText(text)
    if preset then
        local action = Registry and Registry:GetAction("aura_blacklist_add_preset")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, preset = preset },
            label = "Add aura blacklist preset",
            summary = "Adds a curated public spell-ID preset to the selected aura blacklist.",
        } or nil
    end

    local value = AuraBlacklistSpellValue(raw)
    if not value then return nil end
    local remove = ContainsAny(text, { "remove", "delete", "unblacklist", "allow", "loeschen", "entfernen" })
    local action = Registry and Registry:GetAction(remove and "aura_blacklist_remove_spell" or "aura_blacklist_add_spell")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, value = value },
        label = remove and "Remove aura blacklist spell" or "Add aura blacklist spell",
        summary = "Edits the prepared aura blacklist through the Auras3 MenuModel.",
    } or nil
end

local function CopyTextParts(text)
    local src, dst = text:match("^copy%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+from%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopiere%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopieren%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehme%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    return nil, nil
end

local function RemoveUnit(out, unit)
    if not unit then return out end
    local filtered = {}
    for i = 1, #(out or {}) do
        if out[i] ~= unit then filtered[#filtered + 1] = out[i] end
    end
    return filtered
end

local function CopyTargetsForText(text, source)
    if HasPhrase(text, "all") or HasPhrase(text, "all unitframes") or HasPhrase(text, "alle") or HasPhrase(text, "alle unitframes") then
        local targets = {}
        for i = 1, #ALL_UNITFRAMES do
            if ALL_UNITFRAMES[i] ~= source then targets[#targets + 1] = ALL_UNITFRAMES[i] end
        end
        return targets
    end
    return RemoveUnit(DetectUnits(text), source)
end

local function CopyGroupTargetsForText(text, source)
    if HasPhrase(text, "all") or HasPhrase(text, "all groups") or HasPhrase(text, "all group frames") or HasPhrase(text, "alle") or HasPhrase(text, "alle gruppenframes") then
        return RemoveUnit({ "party", "raid", "mythicraid" }, source)
    end
    return RemoveUnit(DetectGroups(text), source)
end

local function ParseGroupCopy(text)
    if not ContainsAny(text, { "copy", "kopieren", "kopiere", "uebernehmen" }) then return nil end
    local source, targets
    local srcText, dstText = CopyTextParts(text)
    if srcText and dstText then
        local srcGroups = DetectGroups(srcText)
        source = srcGroups[1]
        targets = CopyGroupTargetsForText(dstText, source)
    end
    if not source or not targets or #targets == 0 then
        local groups = DetectGroups(text)
        if #groups < 2 then return nil end
        source = groups[1]
        targets = {}
        for i = 2, #groups do targets[#targets + 1] = groups[i] end
    end
    local action = Registry and Registry:GetAction("copy_group")
    if not action then return nil end
    local confirm = ContainsAny(text, { "all", "alle" }) or #targets > 1
    return {
        kind = "action",
        action = action,
        args = { source = source, targets = targets, scopes = GroupCopyScopesForText(text) },
        confirmRequired = confirm,
        label = "Copy " .. tostring((A.UnitLabels or {})[source] or source) .. " group settings",
        summary = "Copies via the existing group-frame copy helper.",
    }
end

local function ParseCopy(text)
    if not ContainsAny(text, { "copy", "kopieren", "kopiere", "uebernehmen" }) then return nil end
    local source, targets
    local srcText, dstText = CopyTextParts(text)
    if srcText and dstText then
        local srcUnits = DetectUnits(srcText)
        source = srcUnits[1]
        targets = CopyTargetsForText(dstText, source)
    end
    if not source or not targets or #targets == 0 then
        local units = DetectUnits(text)
        if #units < 2 then return nil end
        source = units[1]
        targets = {}
        for i = 2, #units do targets[#targets + 1] = units[i] end
    end
    local action = Registry and Registry:GetAction("copy_unit")
    if not action then return nil end
    local confirm = ContainsAny(text, { "all", "alle" }) or #targets > 2
    return {
        kind = "action",
        action = action,
        args = { source = source, targets = targets, scopes = CopyScopesForText(text) },
        confirmRequired = confirm,
        label = "Copy " .. tostring((A.UnitLabels or {})[source] or source) .. " settings",
        summary = "Copies via the existing unit copy helper.",
    }
end

local function BuildContextReset(text, ctx)
    if not (ctx and type(ctx.lastUnit) == "string") then return nil end
    if not ContainsAny(text, { "reset", "restore", "zuruecksetzen", "default", "defaults" }) then return nil end
    if not (HasPhrase(text, "it") or HasPhrase(text, "that") or HasPhrase(text, "das")) then return nil end
    local setting = ctx.lastSetting and Registry:GetSetting(ctx.lastSetting) or nil
    local isPosition = setting and (setting.attribute == "offsetX" or setting.attribute == "offsetY")
    local action = Registry and Registry:GetAction(isPosition and "reset_unit_position" or "reset_unit_page")
    return action and {
        kind = "action",
        action = action,
        args = { unit = ctx.lastUnit },
        confirmRequired = not isPosition,
        label = isPosition and "Reset previous frame position" or "Reset previous frame settings",
        summary = "Uses the last Assistant unit as context.",
    } or nil
end

local GROUP_STATUS_ICON_ALIASES = {
    { key = "roleIcon", aliases = { "role icon", "role indicator" } },
    { key = "leaderIcon", aliases = { "leader icon", "leader indicator" } },
    { key = "assistIcon", aliases = { "assist icon", "assistant icon", "assist indicator" } },
    { key = "raidMarker", aliases = { "raid marker", "raid marker icon", "target marker" } },
    { key = "readyCheckIcon", aliases = { "ready check", "ready check icon", "ready icon" } },
    { key = "summonIcon", aliases = { "summon icon", "summon indicator" } },
    { key = "resurrectIcon", aliases = { "resurrect icon", "resurrection icon", "rez icon", "incoming resurrection" } },
    { key = "phaseIcon", aliases = { "phase icon", "phasing icon", "phase indicator" } },
    { key = "statusText", aliases = { "dead text", "dead status text", "status text" } },
    { key = "statusGhostText", aliases = { "ghost text", "ghost status text" } },
    { key = "statusAFKText", aliases = { "afk text", "dnd text", "afk dnd text", "away text" } },
}

local function GroupStatusIconForText(text)
    for i = 1, #GROUP_STATUS_ICON_ALIASES do
        local row = GROUP_STATUS_ICON_ALIASES[i]
        if ContainsAny(text, row.aliases) then return row.key end
    end
    return nil
end

local GROUP_STATUS_ICON_TERMS = {
    "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators",
    "role icon", "leader icon", "assist icon", "raid marker", "ready check", "summon icon",
    "resurrect icon", "rez icon", "phase icon", "dead text", "ghost text", "afk text", "dnd text",
}

local function FirstGroupOrDefault(text)
    local groups = DetectGroups(text)
    return groups[1] or "party"
end

local function AliasValueForText(text, aliases, values)
    local compactText = Compact(text)
    if type(aliases) == "table" then
        local bestValue, bestLen
        for alias, value in pairs(aliases) do
            local compactAlias = Compact(alias)
            if HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true)) then
                local len = #compactAlias
                if not bestLen or len > bestLen then bestValue, bestLen = value, len end
            end
        end
        if bestValue ~= nil then return bestValue end
    end
    for i = 1, #(values or {}) do
        local value = values[i]
        local compactValue = Compact(value)
        if HasPhrase(text, tostring(value)) or (#compactValue >= 5 and compactText:find(compactValue, 1, true)) then return value end
    end
    return nil
end

local GROUP_SPELL_PLACED_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", icon = "icon", square = "square", dot = "square", bar = "bar", number = "number", text = "number" }
local GROUP_SPELL_FRAME_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", healthtint = "healthtint", ["health tint"] = "healthtint", tint = "healthtint", border = "border", outline = "border", glow = "glow", pulse = "pulse", namecolor = "namecolor", ["name color"] = "namecolor" }
local GROUP_SPELL_GROWTH_ALIASES = { rightdown = "RIGHTDOWN", ["right down"] = "RIGHTDOWN", ["right then down"] = "RIGHTDOWN", leftdown = "LEFTDOWN", ["left down"] = "LEFTDOWN", ["left then down"] = "LEFTDOWN", rightup = "RIGHTUP", ["right up"] = "RIGHTUP", ["right then up"] = "RIGHTUP", leftup = "LEFTUP", ["left up"] = "LEFTUP", ["left then up"] = "LEFTUP" }
local GROUP_SPELL_ANCHOR_ALIASES = { topleft = "TOPLEFT", ["top left"] = "TOPLEFT", topright = "TOPRIGHT", ["top right"] = "TOPRIGHT", bottomleft = "BOTTOMLEFT", ["bottom left"] = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT", ["bottom right"] = "BOTTOMRIGHT", center = "CENTER", centre = "CENTER", middle = "CENTER", top = "TOP", bottom = "BOTTOM", left = "LEFT", right = "RIGHT" }

local function ParseGroupSpellIndicatorAction(text, raw)
    if not ContainsAny(text, { "spell indicator", "spell indicators", "tracked spell", "tracked spells" }) then return nil end
    local scope = FirstGroupOrDefault(text)
    local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(text) or nil

    if ContainsAny(text, { "multi spec", "multispec", "track selected multi spec", "track spec" }) and spec and spec ~= "auto" and spec ~= "multi" then
        local action = Registry and Registry:GetAction("set_group_spell_indicator_multi_spec")
        local value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, { "remove", "clear", "stop" }) end
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, value = value },
            label = "Set group spell indicator multi-spec",
            summary = "Toggles a concrete spec entry in Spell Indicators Multi-Spec mode.",
        } or nil
    end

    local aura, resolvedSpec = A.ResolveGroupSpellAura and A.ResolveGroupSpellAura(spec, text) or nil
    spec = spec or resolvedSpec
    if ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then
        local action = Registry and Registry:GetAction("reset_group_spell_indicator_aura")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, aura = aura or text },
            label = "Reset group spell indicator aura",
            summary = "Resets one tracked spell indicator entry to its defaults.",
        } or nil
    end

    if ContainsAny(text, { "move", "order", "reorder", "first", "last", "slot", "position" }) and aura then
        local action = Registry and Registry:GetAction("move_group_spell_indicator_order")
        local position = FirstNumber(text)
        if ContainsAny(text, { "first", "top", "front" }) then position = 1 end
        if ContainsAny(text, { "last", "bottom", "end" }) then position = 999 end
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, aura = text, position = position or 1 },
            label = "Move group spell indicator order",
            summary = "Changes the tracked spell display order.",
        } or nil
    end

    local field, value
    if ContainsAny(text, { "only my cast", "only mine", "own cast", "cast by me" }) then
        field, value = "onlyOwn", DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, { "cooldown text size", "cooldown font size" }) then
        field, value = "placedCooldownSize", FirstNumber(text)
    elseif ContainsAny(text, { "cooldown swipe" }) then
        field, value = "placedCooldownSwipe", DetectBoolean(text)
    elseif ContainsAny(text, { "cooldown text", "show cooldown" }) then
        field, value = "placedCooldown", DetectBoolean(text)
    elseif ContainsAny(text, { "show when missing", "when missing", "missing indicator" }) then
        field, value = "placedMissing", DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, { "bar width" }) then
        field, value = "placedBarWidth", FirstNumber(text)
    elseif ContainsAny(text, { "growth", "grow" }) then
        field, value = "placedGrowth", AliasValueForText(text, GROUP_SPELL_GROWTH_ALIASES, { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" })
    elseif ContainsAny(text, { "frame color", "effect color", "tint color", "glow color", "border color" }) then
        local r, g, b, label = ExtractColor(raw, text)
        if r then field, value = "frameColor", { r = r, g = g, b = b, label = label } end
    elseif ContainsAny(text, { "frame effect", "effect type", "frame type" }) then
        field, value = "frameType", AliasValueForText(text, GROUP_SPELL_FRAME_ALIASES, { "none", "healthtint", "border", "glow", "pulse", "namecolor" })
    elseif ContainsAny(text, { "frame priority", "effect priority", "priority" }) then
        field, value = "framePriority", FirstNumber(text)
    elseif ContainsAny(text, { "tint alpha", "frame alpha", "effect alpha" }) then
        field, value = "frameAlpha", FirstNumber(text)
        if value and value > 1 then value = value / 100 end
    elseif ContainsAny(text, { "thickness", "border thickness", "glow thickness" }) then
        field, value = "frameThickness", FirstNumber(text)
    elseif ContainsAny(text, { "indicator type", "placed indicator", "placed type", "type" }) then
        field, value = "placedType", AliasValueForText(text, GROUP_SPELL_PLACED_ALIASES, { "none", "icon", "square", "bar", "number" })
    elseif ContainsAny(text, { "anchor", "position" }) then
        field, value = "placedAnchor", AliasValueForText(text, GROUP_SPELL_ANCHOR_ALIASES, { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" })
    elseif ContainsAny(text, { "x offset", "x position", "x" }) then
        field, value = "placedX", FirstNumber(text)
    elseif ContainsAny(text, { "y offset", "y position", "y" }) then
        field, value = "placedY", FirstNumber(text)
    elseif ContainsAny(text, { "size", "icon size" }) then
        field, value = "placedSize", FirstNumber(text)
    else
        value = DetectBoolean(text)
        if value ~= nil then field = "enabled" end
    end

    if not (field and value ~= nil and aura) then return nil end
    local action = Registry and Registry:GetAction("set_group_spell_indicator_aura")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, spec = spec, aura = text, field = field, value = value },
        label = "Set group spell indicator",
        summary = "Configures one tracked spell indicator entry.",
    } or nil
end

local function ParseGroupCornerIndicatorReset(text)
    if not ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "corner indicator", "corner indicators", "corner dot", "corner dots", "custom spell" }) then return nil end
    local scope = FirstGroupOrDefault(text)
    local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
    if slot then
        local action = Registry and Registry:GetAction("reset_group_corner_indicator_slot")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, slot = text },
            label = "Reset group corner indicator slot",
            summary = "Resets one corner indicator slot and clears its custom spell editor state.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_group_corner_indicators")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset group corner indicators",
        summary = "Resets all corner indicator slots for the selected group scope.",
    } or nil
end

local function ParseGroupStatusIconReset(text)
    if not ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, GROUP_STATUS_ICON_TERMS) then return nil end
    local scope = FirstGroupOrDefault(text)
    local icon = GroupStatusIconForText(text)
    if icon then
        local action = Registry and Registry:GetAction("reset_group_status_icon")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, icon = icon },
            label = "Reset group status icon",
            summary = "Resets placement and icon pack for one group status icon.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_group_status_icons")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset group status icons",
        summary = "Resets placement and icon packs for all group status icons in the selected scope.",
    } or nil
end

local function ParseGroupStatusPreview(text)
    if not ContainsAny(text, { "preview", "show all", "current indicator", "all indicators", "all status icons" }) then return nil end
    if not ContainsAny(text, GROUP_STATUS_ICON_TERMS) then return nil end
    local scope = FirstGroupOrDefault(text)
    local icon = GroupStatusIconForText(text)
    local mode = ContainsAny(text, { "show all", "all indicators", "all status icons", "preview all" }) and "all" or "current"
    local action = Registry and Registry:GetAction("preview_group_status_icon")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, icon = icon, mode = mode, text = text },
        label = mode == "all" and "Show all group status icons" or "Preview group status icon",
        summary = "Controls the group-frame status icon preview mode.",
    } or nil
end

local UNIT_STATUS_RESET_TERMS = {
    "status indicator", "status indicators", "status icon", "status icons", "indicator position", "level indicator", "level text",
    "leader icon", "assist icon", "raid marker", "raid marker icon", "raid group", "raid group name",
    "elite icon", "rare icon", "dead text", "status text", "combat indicator", "combat icon",
    "rested indicator", "resting indicator", "incoming rez", "incoming resurrection", "resurrection icon",
}

local function ParseUnitStatusIndicatorReset(text)
    if not ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, UNIT_STATUS_RESET_TERMS) then return nil end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text)
    if not spec then return nil end
    local action = Registry and Registry:GetAction("reset_unit_status_indicator")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit, status = spec.value, text = text },
        label = "Reset " .. tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "status indicator"),
        summary = "Resets placement and style fields for one unit-frame status indicator.",
    } or nil
end

local function ParseUnitStatusPreview(text, ctx)
    if not ContainsAny(text, { "preview", "show all", "current indicator", "all indicators", "all status icons" }) then return nil end
    if not ContainsAny(text, UNIT_STATUS_RESET_TERMS) then return nil end
    local units = DetectUnits(text)
    local unit = units[1] or (ctx and ctx.lastUnit)
    local spec = A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text) or nil
    local mode = ContainsAny(text, { "show all", "all indicators", "all status icons", "preview all" }) and "all" or "current"
    local action = Registry and Registry:GetAction("preview_unit_status_indicator")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit, status = spec and spec.value, mode = mode, text = text },
        label = mode == "all" and "Show all status indicators" or "Preview status indicator",
        summary = "Controls the unit-frame status indicator preview mode.",
    } or nil
end


local function ParseUnitStatusIndicatorMove(text)
    if not ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "verschiebe" }) then return nil end
    local direction = DetectDirection(text)
    if not direction then return nil end
    if not ContainsAny(text, UNIT_STATUS_RESET_TERMS) then return nil end
    local units = DetectUnits(text)
    if #units == 0 then
        local currentUnit = CurrentPageUnit and CurrentPageUnit() or nil
        if currentUnit then units = { currentUnit } end
    end
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text) or nil
    if not spec then return nil end
    local key = (direction == "left" or direction == "right") and spec.x or spec.y
    if type(key) ~= "string" or key == "" then return nil end
    local setting = Registry and Registry:GetSetting(unit .. "." .. key)
    if not setting then return nil end
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    return {
        kind = "changes",
        changes = { { setting = setting, relativeDelta = amount, direction = direction } },
        label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Position",
        summary = "Moves a unit-frame status indicator through its real X/Y offset setting.",
    }
end

local function ParseCustomAnchorWorkflow(text)
    if not ContainsAny(text, { "custom anchor", "custom anchor picker", "anchor picker", "anchor frame picker" }) then return nil end
    if ContainsAny(text, { "cancel", "close", "stop", "abort" }) then
        local action = Registry and Registry:GetAction("cancel_custom_anchor_picker")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Cancel custom anchor picker",
            summary = "Closes the shared custom anchor picker overlay if it is active.",
        } or nil
    end
    if ContainsAny(text, { "status", "active", "is picker", "show picker" }) then
        local action = Registry and Registry:GetAction("custom_anchor_picker_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show custom anchor picker status",
            summary = "Reports whether the custom anchor picker overlay is active.",
        } or nil
    end
    if not ContainsAny(text, { "pick", "picker", "start", "open", "select", "choose" }) then return nil end
    local groups = DetectGroups(text)
    if groups[1] then
        local action = Registry and Registry:GetAction("start_group_custom_anchor_picker")
        return action and {
            kind = "action",
            action = action,
            args = { scope = groups[1] },
            label = "Start group custom anchor picker",
            summary = "Starts the shared custom anchor picker overlay for a group frame.",
        } or nil
    end
    local units = DetectUnits(text)
    local unit = units[1]
    if not unit then return nil end
    local action = Registry and Registry:GetAction("start_unit_custom_anchor_picker")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        label = "Start unit custom anchor picker",
        summary = "Starts the shared custom anchor picker overlay for a unit frame.",
    } or nil
end

local function CleanCustomAnchorFrameName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("[\"'`]", "")
    name = name:gsub("^frame%s+", "")
    name = name:gsub("^name%s+", "")
    name = name:gsub("^named%s+", "")
    name = name:gsub("^called%s+", "")
    name = name:gsub("^to%s+", "")
    name = name:gsub("^as%s+", "")
    name = name:gsub("[%s%.%,;:!%?]+$", "")
    name = Trim(name)
    if name == "" then return nil end
    local lower = Normalize(name)
    if lower == "none" or lower == "free" or lower == "clear" or lower == "default" or lower == "global" then return "" end
    return name
end

local function RawCustomAnchorFrameName(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local connectors = { " to ", " as ", " named ", " called ", " frame ", " name " }
    local bestEnd
    for i = 1, #connectors do
        local start = 1
        while true do
            local s, e = lower:find(connectors[i], start, true)
            if not s then break end
            if not bestEnd or e > bestEnd then bestEnd = e end
            start = e + 1
        end
    end
    if bestEnd then return CleanCustomAnchorFrameName(raw:sub(bestEnd + 1)) end
    return nil
end

local function ParseCustomAnchorSet(text, raw)
    if not ContainsAny(text, { "custom anchor", "custom anchor frame", "anchor frame name" }) then return nil end
    if not ContainsAny(text, { "set", "change", "use", "assign", "write", "apply" }) then return nil end
    local frameName = RawCustomAnchorFrameName(raw)
    if frameName == nil then return nil end

    local groups = DetectGroups(text)
    if #groups > 0 then
        local changes = {}
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".customAnchorFrame")
            if setting then changes[#changes + 1] = { setting = setting, value = frameName } end
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = "Set group custom anchor frame",
            summary = "Writes the Group Layout custom anchor frame name directly, matching the custom anchor text box result.",
        }
    end

    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local setting = Registry and Registry:GetSetting(units[1] .. ".anchorFrameName")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = frameName } },
        label = "Set unit custom anchor frame",
        summary = "Writes the Unit Frame custom anchor frame name directly, matching the custom anchor text box result.",
    }
end

local function ParseCustomAnchorClear(text)
    if not ContainsAny(text, { "clear", "remove", "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "custom anchor", "custom anchor frame", "anchor frame name" }) then return nil end
    local groups = DetectGroups(text)
    if groups[1] then
        local action = Registry and Registry:GetAction("clear_group_custom_anchor")
        return action and {
            kind = "action",
            action = action,
            args = { scope = groups[1] },
            label = "Clear " .. tostring((A.UnitLabels or {})[groups[1]] or groups[1]) .. " custom anchor",
            summary = "Clears the group-frame custom anchor frame name.",
        } or nil
    end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local action = Registry and Registry:GetAction("clear_unit_custom_anchor")
    return action and {
        kind = "action",
        action = action,
        args = { unit = units[1] },
        label = "Clear " .. tostring((A.UnitLabels or {})[units[1]] or units[1]) .. " custom anchor",
        summary = "Clears the unit-frame custom anchor frame name.",
    } or nil
end

local function ParseReset(text)
    if not ContainsAny(text, { "reset", "restore", "zuruecksetzen", "default", "defaults" }) then return nil end
    if ContainsAny(text, { "factory reset", "full reset", "fullreset", "reset all settings", "reset all profiles" }) then
        local action = Registry and Registry:GetAction("factory_reset_all")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Factory reset all MSUF settings",
            summary = "Stages the shared MSUF full factory reset flow without running a slash command.",
        } or nil
    end
    if ContainsAny(text, { "profile", "profil" }) then
        local action = Registry and Registry:GetAction("reset_profile")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset active profile",
            summary = "Resets the active profile.",
        } or nil
    end
    if ContainsAny(text, { "focus kick", "focus interrupt tracker", "focus interrupt", "kick tracker" })
        and ContainsAny(text, { "position", "pos", "placement", "x", "y" })
    then
        local action = Registry and Registry:GetAction("reset_focus_kick_position")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = action.label or "Reset Focus Kick position",
            summary = "Resets the Focus Kick on-screen tracker offsets.",
        } or nil
    end
    if ContainsAny(text, { "all positions", "frame positions", "reset positions", "reset movers", "offscreen", "off screen", "broken layout", "alle positionen" }) then
        local action = Registry and Registry:GetAction("reset_all_unit_positions")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset all unit-frame positions",
            summary = "Restores default unit-frame anchors and offsets.",
        } or nil
    end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local unit = units[1]
    if ContainsAny(text, { "position", "pos", "placement", "frame position", "x", "y" }) then
        local action = Registry and Registry:GetAction("reset_unit_position")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Reset " .. tostring((A.UnitLabels or {})[unit] or unit) .. " position",
            summary = "Restores default anchor and offsets.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_unit_page")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        confirmRequired = true,
        label = "Reset " .. tostring((A.UnitLabels or {})[unit] or unit) .. " settings",
        summary = "Resets all settings on that unit page.",
    } or nil
end

local function ParseOpen(text, raw)
    local explicit = ContainsAny(text, { "open", "go to", "show settings", "show me", "find", "search", "oeffne" })
    local shortcut = false
    if not explicit and DetectBoolean(text) == nil and FirstNumber(text) == nil then
        shortcut = ContainsAny(text, { "settings", "menu", "page", "options", "config", "configuration", "einstellungen", "menue", "seite" })
        if not shortcut then
            for i = 1, #PAGE_TEXT_TARGETS do
                local spec = PAGE_TEXT_TARGETS[i]
                for j = 1, #(spec.terms or {}) do
                    if text == Normalize(spec.terms[j]) then
                        shortcut = true
                        break
                    end
                end
                if shortcut then break end
            end
        end
    end
    if not explicit and not shortcut then return nil end
    local page, label = PageForText(text)
    if not page then return nil end
    local action = Registry and Registry:GetAction("open_page")
    return action and {
        kind = "action",
        action = action,
        args = { page = page, label = label, query = raw or text },
        label = "Open " .. label,
        summary = "Navigates the Dashboard.",
    } or nil
end

local function DashboardPanelForText(text)
    if ContainsAny(text, { "recovery tools", "display recovery", "recover menu", "reset tools", "dashboard recovery", "recovery panel", "display panel" }) then return "recovery", "recovery tools" end
    if ContainsAny(text, { "scaling tools", "dashboard scaling", "scale tools", "ui scale tools", "scaling panel", "scale panel" }) then return "scaling", "scaling tools" end
    if ContainsAny(text, { "changelog", "change log", "release notes", "latest changes", "build notes", "changelog panel" }) then return "changelog", "changelog" end
    return nil, nil
end

local function ParseDashboardPanelAction(text)
    local panel, label = DashboardPanelForText(text)
    if not panel then return nil end
    local explicit = ContainsAny(text, { "open", "show", "close", "hide", "collapse", "expand", "toggle" })
    if not explicit then return nil end
    local open
    if ContainsAny(text, { "close", "hide", "collapse" }) then
        open = false
    elseif ContainsAny(text, { "toggle" }) then
        open = nil
    else
        open = true
    end
    local action = Registry and Registry:GetAction("set_dashboard_panel")
    return action and {
        kind = "action",
        action = action,
        args = { panel = panel, open = open },
        label = (open == false and "Close " or (open == nil and "Toggle " or "Open ")) .. label,
        summary = "Controls the persisted Dashboard panel disclosure state.",
    } or nil
end

local NAV_SECTION_TEXT_TARGETS = {
    { section = "groupframes", label = "Group Frames", terms = { "group frames", "groupframes", "raid frames", "party frames", "group frame", "groups" } },
    { section = "unitframes", label = "Frames", terms = { "frames", "unitframes", "unit frames", "unit frame", "frame list" } },
    { section = "globalstyle", label = "Appearance", terms = { "appearance", "global style", "globalstyle", "style section", "look section" } },
    { section = "modules", label = "Advanced", terms = { "advanced", "modules", "module section", "advanced menu" } },
    { section = "auras", label = "Auras", terms = { "auras", "aura section", "buffs section", "debuffs section" } },
}

local function NavSectionForText(text)
    for i = 1, #NAV_SECTION_TEXT_TARGETS do
        local spec = NAV_SECTION_TEXT_TARGETS[i]
        if ContainsAny(text, spec.terms) then return spec.section, spec.label end
    end
    return nil, nil
end

local function ParseNavRailAction(text)
    if ContainsAny(text, { "search intro", "ask msuf intro", "assistant search intro", "search help intro" }) then
        local command
        if ContainsAny(text, { "hide", "close", "dismiss", "mark seen", "mark as seen", "dont show" }) then
            command = "seen"
        elseif ContainsAny(text, { "reset", "show again", "next time" }) then
            command = "reset"
        elseif ContainsAny(text, { "show", "open" }) then
            command = "show"
        end
        if not command then return nil end
        local action = Registry and Registry:GetAction("set_nav_search_intro")
        return action and {
            kind = "action",
            action = action,
            args = { command = command },
            label = "Set search intro",
            summary = "Controls the NavRail search intro state.",
        } or nil
    end

    if not ContainsAny(text, { "navigation section", "nav section", "sidebar section", "left nav section", "section", "navigation group", "nav group", "sidebar group" }) then return nil end
    if not ContainsAny(text, { "open", "show", "close", "hide", "collapse", "expand", "toggle" }) then return nil end
    local section, label = NavSectionForText(text)
    if not section then return nil end
    local open
    if ContainsAny(text, { "close", "hide", "collapse" }) then
        open = false
    elseif ContainsAny(text, { "toggle" }) then
        open = nil
    else
        open = true
    end
    local action = Registry and Registry:GetAction("set_nav_section")
    return action and {
        kind = "action",
        action = action,
        args = { section = section, open = open },
        label = (open == false and "Close " or (open == nil and "Toggle " or "Open ")) .. label .. " navigation section",
        summary = "Controls the NavRail section disclosure state.",
    } or nil
end

local function ParseMenuWindowAction(text)
    if ContainsAny(text, { "panel", "tools", "changelog", "change log", "release notes" }) then return nil end
    if not ContainsAny(text, { "menu", "dashboard", "options", "options window", "msuf menu", "msuf window" }) then return nil end
    local actionKey
    local label
    if ContainsAny(text, { "minimize", "minimise", "collapse" }) then
        actionKey = "menu_window_minimize"
        label = "Minimize MSUF menu"
    elseif ContainsAny(text, { "maximize", "maximise", "fullscreen", "full screen" }) then
        actionKey = "menu_window_maximize"
        label = "Maximize MSUF menu"
    elseif ContainsAny(text, { "restore", "unminimize", "unminimise", "show minimized" }) then
        actionKey = "menu_window_restore"
        label = "Restore MSUF menu"
    elseif ContainsAny(text, { "close", "hide" }) then
        actionKey = "menu_window_close"
        label = "Close MSUF menu"
    end
    local action = actionKey and Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = {},
        label = label,
        summary = "Controls the shared MSUF Menu2 window helpers.",
    } or nil
end

local function SettingMatchesText(setting, text)
    if type(setting) ~= "table" then return false end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        local wantedGroup
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wantedGroup = "mythicraid"
        elseif HasPhrase(text, "party") then
            wantedGroup = "party"
        elseif HasPhrase(text, "raid") then
            wantedGroup = "raid"
        end
        if wantedGroup and setting.unit ~= wantedGroup then return false end
    end
    local relationText = AliasRelationText(text)
    local aliases = setting.aliases or {}
    for i = 1, #aliases do
        if TextMatchesAlias(text, relationText, aliases[i]) then return true end
    end
    if setting.matchLabel ~= false and setting.label and TextMatchesAlias(text, relationText, setting.label) then return true end
    return false
end

local function SettingMatchScore(setting, text)
    if type(setting) ~= "table" then return 0 end
    if setting.frameType == "castbar" and setting.attribute == "enabled" and ContainsAny(text, CASTBAR_ROOT_DETAIL_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) and not ContainsAny(text, CLASS_POWER_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, { "portrait", "portrait border" }) and not ContainsAny(text, CLASS_POWER_TERMS) then
        return 0
    end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        local wantedGroup
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wantedGroup = "mythicraid"
        elseif HasPhrase(text, "party") then
            wantedGroup = "party"
        elseif HasPhrase(text, "raid") then
            wantedGroup = "raid"
        end
        if wantedGroup and setting.unit ~= wantedGroup then return 0 end
    end

    local best = 0
    local relationText = AliasRelationText(text)
    local aliases = setting.aliases or {}
    for i = 1, #aliases do
        if TextMatchesAlias(text, relationText, aliases[i]) then
            local score = #Compact(aliases[i])
            if score > best then best = score end
        end
    end
    if setting.matchLabel ~= false and setting.label and TextMatchesAlias(text, relationText, setting.label) then
        local score = #Compact(setting.label)
        if score > best then best = score end
    end
    return best
end

local function EnumValueForText(setting, text)
    local aliases = setting and setting.valueAliases
    local compactText = Compact(text)
    if type(aliases) == "table" then
        local bestValue
        local bestLen = 0
        for alias, value in pairs(aliases) do
            local compactAlias = Compact(alias)
            if HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true)) then
                local len = #Compact(alias)
                if len > bestLen then
                    bestLen = len
                    bestValue = value
                end
            end
        end
        if bestValue ~= nil then return bestValue end
    end
    local values = setting and setting.values
    if type(values) == "table" then
        for i = 1, #values do
            local value = values[i]
            local compactValue = Compact(value)
            if HasPhrase(text, tostring(value)) or (#compactValue >= 5 and compactText:find(compactValue, 1, true)) then return value end
        end
    end
    return nil
end

local function StringValueForText(setting, text, raw)
    local rawText = tostring(raw or "")
    local quoted = rawText:match("\"([^\"]*)\"") or rawText:match("'([^']*)'")
    if quoted ~= nil then return quoted end
    local rawLower = rawText:lower()
    local prefixes = setting and setting.valuePrefixes or setting and setting.aliases or {}
    for i = 1, #(prefixes or {}) do
        local prefix = Normalize(prefixes[i])
        if prefix ~= "" then
            local rawStart, rawEnd = (" " .. rawLower .. " "):find(" " .. tostring(prefixes[i] or ""):lower() .. " ", 1, true)
            if rawStart then
                local value = Trim(rawText:sub(rawEnd))
                value = value:gsub("^%s*[Tt][Oo]%s+", ""):gsub("^%s*[Aa][Ss]%s+", ""):gsub("^%s*[Ii][Ss]%s+", ""):gsub("^%s*[Bb][Ee]%s+", "")
                value = Trim(value)
                if value ~= "" then return value end
            end
            local startPos, endPos = (" " .. text .. " "):find(" " .. prefix .. " ", 1, true)
            if startPos then
                local value = Trim(text:sub(endPos))
                value = value:gsub("^to%s+", ""):gsub("^as%s+", ""):gsub("^is%s+", ""):gsub("^be%s+", "")
                value = Trim(value)
                if value ~= "" then return value end
            end
        end
    end
    return nil
end

local RELATIVE_INCREASE_TERMS = {
    "increase", "raise", "bump up", "more", "higher", "larger", "bigger", "wider", "taller", "thicker", "grow", "add",
    "erhoehe", "erhoehen", "hoeher", "groesser", "mehr", "breiter", "dicker",
}
local RELATIVE_DECREASE_TERMS = {
    "decrease", "reduce", "lower", "less", "smaller", "narrower", "shorter", "thinner", "shrink", "subtract", "down",
    "verringere", "reduziere", "tiefer", "niedriger", "kleiner", "weniger", "schmaler", "duenner", "runter",
}

local function RelativeNumberDeltaForText(setting, text, fallbackAmount)
    local sign
    if ContainsAny(text, RELATIVE_INCREASE_TERMS) then sign = 1 end
    if ContainsAny(text, RELATIVE_DECREASE_TERMS) then sign = -1 end
    if not sign then return nil end
    local amount = FirstNumber(text)
    if amount == nil then
        amount = fallbackAmount
            or (setting and tonumber(setting.step))
            or 1
    end
    if setting and setting.percent == true and amount > 1 then amount = amount / 100 end
    return amount * sign
end

local function NumberSettingSupportsBooleanToggle(setting)
    if type(setting) ~= "table" then return false end
    local hay = (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")):lower()
    return hay:find("outline", 1, true) ~= nil
        or hay:find("border", 1, true) ~= nil
        or hay:find("thickness", 1, true) ~= nil
end

local function BooleanValueForNumberSetting(setting, text)
    if not NumberSettingSupportsBooleanToggle(setting) then return nil end
    if not ContainsAny(text, { "on", "off", "enable", "disable", "show", "hide", "an", "aus", "aktivieren", "deaktivieren" }) then return nil end
    local bool = DetectBoolean(text)
    if bool == nil then return nil end
    if bool == false then
        local minValue = tonumber(setting.min)
        if minValue ~= nil then return minValue end
        return 0
    end
    local step = tonumber(setting.step) or 1
    local minValue = tonumber(setting.min)
    local maxValue = tonumber(setting.max)
    local value = step
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function ValueForRegistrySetting(setting, text, raw)
    if not setting then return nil end
    if setting.type == "boolean" then
        local attr = tostring(setting.attribute or ""):lower()
        local key = tostring(setting.key or ""):lower()
        if key == "general.hardkillblizzardplayerframe" then
            if ContainsAny(text, { "turn off", "disable", "disabled", "off", "false", "no" }) then return false end
            if ContainsAny(text, { "fully hide", "hard hide", "hard kill", "enable", "enabled", "turn on", "on", "true", "yes" }) then return true end
            return DetectBoolean(text)
        end
        if attr:find("^hide") or key:find("hide") then
            if ContainsAny(text, { "turn off", "disable", "disabled", "off", "false", "no", "dont hide", "do not hide", "never hide", "always show", "show" }) then return false end
            if ContainsAny(text, { "hide", "enable", "enabled", "turn on", "on", "true", "yes" }) then return true end
        end
        return DetectBoolean(text)
    end
    if setting.type == "number" then
        local boolValue = BooleanValueForNumberSetting(setting, text)
        if boolValue ~= nil then return boolValue end
        local value = FirstNumber(text)
        if value and setting.percent == true and value > 1 then value = value / 100 end
        return value
    end
    if setting.type == "enum" then return EnumValueForText(setting, text) end
    if setting.type == "string" then return StringValueForText(setting, text, raw) end
    if setting.type == "color" then
        local r, g, b, label = ExtractColor(raw, text)
        if r then return { r = r, g = g, b = b, label = label } end
    end
    return nil
end

local function AddMediaResolverChanges(changes, setting, text, raw, score)
    local resolver = A.MediaResolver
    if not (resolver and type(resolver.ResolveSetting) == "function") then return false end
    local media = resolver.ResolveSetting(setting, text, raw)
    if not media then return false end
    if media.status == "exact" and media.value ~= nil then
        changes[#changes + 1] = {
            setting = setting,
            value = media.value,
            matchScore = score,
            valueLabel = media.label or media.value,
            label = tostring(setting.label or "Setting") .. " → " .. tostring(media.label or media.value),
            mediaType = media.mediaType,
        }
        return true
    end
    if media.status == "choices" and type(media.choices) == "table" and #media.choices > 0 then
        for i = 1, #media.choices do
            local item = media.choices[i]
            changes[#changes + 1] = {
                setting = setting,
                value = item.value,
                matchScore = score,
                valueLabel = item.label or item.value,
                label = tostring(setting.label or "Setting") .. " → " .. tostring(item.label or item.value),
                mediaType = media.mediaType,
            }
        end
        return true
    end
    if media.status == "none" then
        changes[#changes + 1] = {
            setting = setting,
            value = nil,
            matchScore = score,
            mediaNoMatch = true,
            mediaType = media.mediaType,
            mediaQuery = media.query,
        }
        return true
    end
    return false
end

local function ParseRegistryAlias(text, raw)
    local settings = Registry and Registry:AllSettings() or {}
    local changes = {}
    local bestScore = 0
    for i = 1, #settings do
        local setting = settings[i]
        local score = SettingMatchScore(setting, text)
        if score > 0 and A.Knowledge and type(A.Knowledge.SettingPageBoost) == "function" then
            score = score + A.Knowledge.SettingPageBoost(setting)
        end
        if score > 0 then
            local handledMedia = false
            if setting.type == "string" then
                handledMedia = AddMediaResolverChanges(changes, setting, text, raw, score)
            end
            if not handledMedia then
                local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText(setting, text) or nil
                local value
                if relativeDelta == nil then value = ValueForRegistrySetting(setting, text, raw) end
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, matchScore = score }
                    if score > bestScore then bestScore = score end
                end
            else
                if score > bestScore then bestScore = score end
            end
        end
    end
    if #changes == 0 then return nil end
    if #changes == 1 and changes[1].mediaNoMatch then
        local resolver = A.MediaResolver
        local textOut = resolver and resolver.NoMatchMessage and resolver.NoMatchMessage(changes[1].mediaType, changes[1].mediaQuery) or "I could not find that media entry."
        return { kind = "unknown", text = textOut, status = "failed" }
    end
    local usable = {}
    for i = 1, #changes do
        if not changes[i].mediaNoMatch then usable[#usable + 1] = changes[i] end
    end
    changes = usable
    if #changes == 0 then return nil end
    if #changes > 1 and bestScore > 0 then
        local filtered = {}
        for i = 1, #changes do
            if changes[i].matchScore == bestScore then filtered[#filtered + 1] = changes[i] end
        end
        if #filtered == 1 then changes = filtered end
    end
    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching settings",
        }
    end
    local setting = changes[1].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Assistant setting change",
        summary = "Registry-backed settings change.",
    }
end

local function ScopedOnlyKind(text)
    if not ContainsAny(text, { "only", "nur", "just" }) then return nil end
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if ContainsAny(text, { "font", "fonts", "schrift", "text outline", "font outline", "text shadow", "name color", "name shortening", "text size" }) then
        return "fonts"
    end
    if ContainsAny(text, { "bars", "bar", "bar texture", "health bar", "hp bar", "power bar", "gradient", "absorb", "outline", "border", "dispel", "aggro", "purge" }) then
        return "globalBars"
    end
    return nil
end

local function ScopedOnlyOverrideKey(kind, scope)
    if kind == "fonts" then return "fontScope." .. tostring(scope or "") .. ".override" end
    if kind == "globalBars" then return "barScope." .. tostring(scope or "") .. ".override" end
    return nil
end

local function ParseScopedOnlyOverride(text, raw)
    local kind = ScopedOnlyKind(text)
    if not kind then return nil end
    local scope = DetectGlobalScope(text)
    if not scope or scope == "shared" then return nil end
    local matchText = " " .. text .. " "
    matchText = matchText:gsub(" only ", " "):gsub(" just ", " "):gsub(" nur ", " ")
    if kind == "globalBars" then
        matchText = matchText:gsub(" bars ", " ")
    elseif kind == "fonts" then
        matchText = matchText:gsub(" fonts ", " font ")
    end
    matchText = Normalize(matchText)

    local candidates = Registry and Registry:FindSettings({ unit = scope, frameType = kind }) or {}
    local changes = {}
    local bestScore = 0
    local overrideKey = ScopedOnlyOverrideKey(kind, scope)
    local overrideSetting = overrideKey and Registry and Registry:GetSetting(overrideKey)

    for i = 1, #candidates do
        local setting = candidates[i]
        if setting and setting.key ~= overrideKey then
            local score = math.max(SettingMatchScore(setting, text), SettingMatchScore(setting, matchText))
            if score > 0 then
                local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText(setting, matchText) or nil
                local value
                if relativeDelta == nil then value = ValueForRegistrySetting(setting, matchText, raw) end
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, matchScore = score }
                    if score > bestScore then bestScore = score end
                end
            end
        end
    end

    if #changes > 1 and bestScore > 0 then
        local filtered = {}
        for i = 1, #changes do
            if changes[i].matchScore == bestScore then filtered[#filtered + 1] = changes[i] end
        end
        changes = filtered
    end

    if #changes == 0 then
        local value = DetectBoolean(text)
        if value == nil then return nil end
        if not overrideSetting then return nil end
        return {
            kind = "changes",
            changes = { { setting = overrideSetting, value = value } },
            label = overrideSetting.label or "Scoped override",
            summary = "Uses ONLY as a scoped Bars/Fonts override command.",
        }
    end

    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching scoped settings",
        }
    end

    if overrideSetting then
        table.insert(changes, 1, { setting = overrideSetting, value = true })
    end
    local setting = changes[#changes].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Scoped override setting",
        summary = "Uses ONLY to enable the scoped Bars/Fonts override before applying the requested setting.",
    }
end

local CLASS_POWER_DETAIL_TERMS = {
    "height", "width", "mode", "x", "y", "offset", "frame level",
    "anchor", "cooldown", "combo", "text", "rune", "reverse", "fill",
    "maelstrom", "ebon", "insanity", "shadow", "prediction", "color",
    "font", "opacity", "alpha", "background", "foreground", "texture", "separator", "tick",
    "outline", "border", "gap", "hide out of combat", "hide when full",
    "hide when empty", "out of combat", "full", "empty", "alt mana",
    "alternative mana", "detached power",
}

local function ParseClassPowerRootToggle(text)
    local value = DetectBoolean(text)
    if value == nil then return nil end
    if not ContainsAny(text, CLASS_POWER_TERMS) then return nil end
    if ContainsAny(text, CLASS_POWER_DETAIL_TERMS) then return nil end
    local setting = Registry and Registry:GetSetting("bars.showClassPower")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Class Resource",
        summary = "Toggles MSUF Class Resources.",
    } or nil
end

local function ParseFontColorAction(text, raw)
    if not ContainsAny(text, { "font color", "text color", "global font color", "schriftfarbe", "textfarbe" }) then return nil end
    if ContainsAny(text, {
            "castbar", "combat", "aura", "stack", "cooldown", "power", "hp", "health",
            "name", "boss target", "mouseover", "dispel", "bar", "npc", "portrait",
        })
        and not ContainsAny(text, { "global", "main", "default" })
    then
        return nil
    end
    if ContainsAny(text, { "reset", "default", "palette", "zuruecksetzen" }) then
        local action = Registry and Registry:GetAction("reset_global_font_color")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Reset global font color",
            summary = "Returns global font color to palette behavior.",
        } or nil
    end
    local r, g, b, label = ExtractColor(raw, text)
    if not r then return nil end
    local action = Registry and Registry:GetAction("set_global_font_color")
    return action and {
        kind = "action",
        action = action,
        args = { r = r, g = g, b = b, label = label },
        label = "Set global font color",
        summary = "Applies a global custom font color.",
    } or nil
end

local function BuildColorResetAction(key, label, summary)
    local action = Registry and Registry:GetAction(key)
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = true,
        label = label,
        summary = summary or "Resets an MSUF color section.",
    } or nil
end

local POWER_TOKEN_EXTRA_ALIASES = {
    MANA = { "mana" },
    RAGE = { "rage" },
    ENERGY = { "energy" },
    FOCUS = { "focus power", "hunter focus" },
    RUNIC_POWER = { "runic power" },
    INSANITY = { "insanity power" },
    FURY = { "fury power" },
    PAIN = { "pain power" },
    ESSENCE = { "essence power" },
    LUNAR_POWER = { "astral power", "lunar power" },
    MAELSTROM = { "maelstrom power" },
}

local function PowerColorTokenForText(text)
    local tokens = A.PowerColorTokens or {}
    local bestToken
    local bestLen = 0
    local function Consider(token, alias)
        if not token or not alias then return end
        if HasPhrase(text, alias) then
            local len = #Compact(alias)
            if len > bestLen then
                bestLen = len
                bestToken = token
            end
        end
    end
    for i = 1, #(tokens or {}) do
        local spec = tokens[i]
        local token = spec and spec.key
        Consider(token, spec and spec.label)
        Consider(token, token and token:gsub("_", " "))
        local extra = token and POWER_TOKEN_EXTRA_ALIASES[token]
        for j = 1, #(extra or {}) do Consider(token, extra[j]) end
    end
    return bestToken
end

local CP_TOKEN_EXTRA_ALIASES = {
    COMBO_POINTS = { "combo point", "combo points" },
    CHARGED = { "charged combo point", "charged combo points", "empowered combo point", "empowered combo points" },
    SOUL_FRAGMENTS_META = { "soul fragments void meta", "void meta soul fragments" },
    MAELSTROM = { "maelstrom", "maelstrom weapon" },
    MAELSTROM_ABOVE_5 = { "maelstrom above 5", "maelstrom weapon above 5", "maelstrom 5+", "maelstrom weapon 5+" },
    ASTRAL_POWER = { "astral power" },
    AP_PREDICTION = { "astral prediction", "astral power prediction" },
    ECLIPSE_CA = { "celestial alignment", "ca eclipse" },
    STAGGER_GREEN = { "stagger light", "light stagger", "green stagger" },
    STAGGER_YELLOW = { "stagger moderate", "moderate stagger", "yellow stagger" },
    STAGGER_RED = { "stagger heavy", "heavy stagger", "red stagger" },
    SOUL_FRAGMENTS_VENG = { "soul fragments vengeance", "vengeance soul fragments" },
    MAELSTROM_POWER = { "maelstrom power" },
    TIP_OF_THE_SPEAR = { "tip of the spear" },
    EBON_MIGHT = { "ebon might" },
    RESOURCE_TEXT = { "resource text", "class resource text", "class power text" },
}

local function ClassPowerColorTokenForText(text)
    local tokens = A.ClassPowerColorTokens or {}
    local bestToken
    local bestLen = 0
    local function Consider(token, alias)
        if not token or not alias then return end
        if HasPhrase(text, alias) then
            local len = #Compact(alias)
            if len > bestLen then
                bestLen = len
                bestToken = token
            end
        end
    end
    for i = 1, #(tokens or {}) do
        local spec = tokens[i]
        local token = spec and spec.key
        Consider(token, spec and spec.label)
        Consider(token, token and token:gsub("_", " "))
        local extra = token and CP_TOKEN_EXTRA_ALIASES[token]
        for j = 1, #(extra or {}) do Consider(token, extra[j]) end
    end
    for i = 1, 7 do
        local token = "COMBO_POINTS_" .. tostring(i)
        Consider(token, "combo point " .. tostring(i))
        Consider(token, "combo point slot " .. tostring(i))
        Consider(token, "cp " .. tostring(i))
    end
    return bestToken
end

local function ParseColorAction(text)
    if not ContainsAny(text, { "reset", "default", "defaults", "restore", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then return nil end
    if ContainsAny(text, { "combo point slot", "combo point slots", "combo slot", "combo slots" }) then
        local action = Registry and Registry:GetAction("reset_class_power_combo_slot_colors")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Reset combo point slot colors",
            summary = "Resets the custom Class Resource combo point slot colors.",
        } or nil
    end
    local powerToken = PowerColorTokenForText(text)
    if powerToken
        and ContainsAny(text, { "power color", "power bar", "powerbar", "resource color", "resource bar", "mana color", "rage color", "energy color", "runic power", "astral power", "maelstrom color" })
        and not ContainsAny(text, { "class power", "class resource", "combo point", "combo points", "holy power", "soul shard", "soul shards", "chi", "arcane charge", "arcane charges", "runes" })
    then
        local action = Registry and Registry:GetAction("reset_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = powerToken },
            label = "Reset power bar token color",
            summary = "Resets a single Power Bar color token.",
        } or nil
    end
    local cpToken = ClassPowerColorTokenForText(text)
    if cpToken and ContainsAny(text, { "class power", "class resource", "resource", "combo", "soul", "maelstrom", "astral", "eclipse", "stagger", "icicles", "ebon", "whirlwind", "tip of the spear", "insanity", "runes", "chi", "essence" }) then
        local action = Registry and Registry:GetAction("reset_class_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = cpToken, background = ContainsAny(text, { "background", "bg" }) },
            label = "Reset class resource token color",
            summary = "Resets a single Class Resource foreground or background token color.",
        } or nil
    end
    if ContainsAny(text, { "castbar", "cast bar" }) then
        return BuildColorResetAction("reset_castbar_colors", "Reset castbar colors", "Resets castbar colors through the existing Colors page state.")
    end
    if ContainsAny(text, { "npc type", "npc role" }) then
        return BuildColorResetAction("reset_npc_type_colors", "Reset NPC type colors", "Resets NPC type colors.")
    end
    if ContainsAny(text, { "unitframe", "unit frame", "npc reaction", "reaction color" }) then
        return BuildColorResetAction("reset_unitframe_colors", "Reset unitframe colors", "Resets unitframe NPC reaction colors.")
    end
    if ContainsAny(text, { "bar background", "background tint", "bar tint" }) then
        return BuildColorResetAction("reset_bar_background_color", "Reset bar background tint", "Resets the global bar background tint.")
    end
    if ContainsAny(text, { "bar color", "bar colors", "absorb", "aggro", "purge", "outline", "border" }) then
        return BuildColorResetAction("reset_bar_colors", "Reset bar colors", "Resets bar overlay and border colors.")
    end
    if ContainsAny(text, { "dispel", "debuff type" }) then
        return BuildColorResetAction("reset_dispel_colors", "Reset dispel colors", "Resets dispel border and debuff-type colors.")
    end
    if ContainsAny(text, { "gameplay", "combat timer", "combat state", "crosshair" }) then
        return BuildColorResetAction("reset_gameplay_colors", "Reset gameplay colors", "Resets Gameplay color settings.")
    end
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "pandemic" }) then
        return BuildColorResetAction("reset_aura_colors", "Reset aura colors", "Resets Aura color settings.")
    end
    if ContainsAny(text, { "portrait" }) then
        return BuildColorResetAction("reset_portrait_colors", "Reset portrait colors", "Resets portrait color settings.")
    end
    if ContainsAny(text, { "resource", "power color", "class power", "class resource", "combo point" }) then
        return BuildColorResetAction("reset_resource_colors", "Reset resource colors", "Resets power and class-resource color overrides.")
    end
    if ContainsAny(text, { "class color", "class colors", "class bar" }) then
        return BuildColorResetAction("reset_class_colors", "Reset class bar colors", "Resets class bar color overrides.")
    end
    return nil
end

local function ParseDiagnostic(text)
    if not ContainsAny(text, { "diagnose", "diagnostic", "troubleshoot", "why", "wieso", "warum", "not showing", "not visible", "missing", "doesnt show", "does not show", "hidden", "nicht sichtbar", "zeigt nicht" }) then return nil end
    if ContainsAny(text, { "castbar", "zauberleiste" }) then
        local units = DetectUnits(text)
        local unit = units[1] or "target"
        local action = Registry and Registry:GetAction("diagnose_castbar_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Diagnose " .. tostring((A.UnitLabels or {})[unit] or unit) .. " castbar",
            summary = "Inspects current castbar settings and suggests the next safe fix.",
        } or nil
    end
    local groups = DetectGroups(text)
    if #groups > 0 or ContainsAny(text, { "group frames", "gruppenframes", "party frames", "raid frames", "mythic raid frames" }) then
        local scope = groups[1] or "party"
        if scope == "mythicraid" then scope = "mythicraid" end
        local action = Registry and Registry:GetAction("diagnose_group_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope },
            label = "Diagnose " .. tostring((A.UnitLabels or {})[scope] or scope) .. " group frames",
            summary = "Inspects current group-frame settings and suggests the next safe fix.",
        } or nil
    end
    local units = DetectUnits(text)
    if #units > 0 then
        local unit = units[1]
        local action = Registry and Registry:GetAction("diagnose_unit_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Diagnose " .. tostring((A.UnitLabels or {})[unit] or unit) .. " frame",
            summary = "Inspects current unit-frame settings and suggests the next safe fix.",
        } or nil
    end
    return nil
end

local function ParseScopedHelp(text)
    if not ContainsAny(text, {
        "what can i change", "what can change", "what settings can i change",
        "what can i do here", "what can i change here", "commands for",
        "show commands for", "help for", "help with", "help me with",
    }) then return nil end
    local action = Registry and Registry:GetAction("assistant_scope_help")
    if not action then return nil end
    local page, label = PageForText(text)
    if not page and ContainsAny(text, { "here", "current page", "this page" }) then
        page = M and M.activeKey
        label = "current page"
    end
    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    local unit = units[1]
    local group = groups[1]
    local frameType = FrameTypeForPage(page)
    if group then
        frameType = ContainsAny(text, { "aura", "auras", "buff", "debuff" }) and "groupAura" or "group"
        label = (A.UnitLabels and A.UnitLabels[group]) or label
    elseif unit then
        frameType = ContainsAny(text, { "castbar", "cast bar" }) and "castbar" or "unitframe"
        label = (A.UnitLabels and A.UnitLabels[unit]) or label
    elseif not frameType then
        frameType = DetectFrameType(text, {})
    end
    return {
        kind = "action",
        action = action,
        args = { page = page, label = label, frameType = frameType, unit = unit, group = group },
        label = "Show scoped Assistant help",
        summary = "Shows registry-backed commands for the requested area.",
    }
end

local function SupportLinkForText(text)
    if ContainsAny(text, { "discord", "discord link", "support discord" }) then return "discord" end
    if ContainsAny(text, { "patreon", "patreon link" }) then return "patreon" end
    if ContainsAny(text, { "paypal", "pay pal", "paypal link" }) then return "paypal" end
    if ContainsAny(text, { "ko fi", "kofi", "ko-fi" }) then return "kofi" end
    if ContainsAny(text, { "github", "repository", "repo link" }) then return "github" end
    return nil
end

local function ParseSupportWorkflow(text)
    if ContainsAny(text, {
        "msuf status", "assistant status", "status report", "diagnostic report",
        "diagnostics", "debug summary", "version info", "locale info",
    }) then
        local action = Registry and Registry:GetAction("assistant_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show MSUF status",
            summary = "Shows read-only MSUF and Assistant diagnostic status.",
        } or nil
    end

    if text == "help" or text == "hilfe" or ContainsAny(text, {
        "assistant help", "command help", "commands help", "help commands",
        "print help", "show help", "what can you do", "what settings can you change",
        "command examples",
    }) then
        local action = Registry and Registry:GetAction("assistant_help")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant help",
            summary = "Shows deterministic Assistant command examples.",
        } or nil
    end

    if ContainsAny(text, { "edit mode", "move frames", "drag frames", "position frames" }) then
        local actionKey = "assistant.action.editMode.enter"
        local label = "Enter MSUF Edit Mode"
        local args = {}
        if ContainsAny(text, {
            "am i in edit mode", "is edit mode on", "is edit mode active", "edit mode status",
            "why can't i exit edit mode", "why cant i exit edit mode", "why can not i exit edit mode",
            "why can't leave edit mode", "why cant leave edit mode",
        }) then
            actionKey = "assistant.diagnostic.editMode.status"
            label = "Show MSUF Edit Mode status"
            if ContainsAny(text, { "why can't", "why cant", "why can not" }) then args.reason = "why_exit" end
        elseif ContainsAny(text, { "cancel edit mode", "discard edit mode", "cancel msuf edit mode", "cancel all edit mode" }) then
            actionKey = "assistant.action.editMode.cancel"
            label = "Cancel MSUF Edit Mode"
        elseif ContainsAny(text, { "toggle edit mode", "toggle msuf edit mode" }) then
            actionKey = "assistant.action.editMode.toggle"
            label = "Toggle MSUF Edit Mode"
        elseif ContainsAny(text, {
            "stop edit mode", "exit edit mode", "exit msuf edit mode", "leave edit mode", "leave msuf edit mode",
            "close edit mode", "close msuf edit mode", "disable edit mode", "turn off edit mode", "edit mode off",
        }) then
            actionKey = "assistant.action.editMode.exit"
            label = "Exit MSUF Edit Mode"
        end
        local action = Registry and Registry:GetAction(actionKey)
        return action and {
            kind = "action",
            action = action,
            args = args,
            confirmRequired = actionKey == "assistant.action.editMode.cancel",
            label = label,
            summary = "Controls the shared MSUF Edit Mode lifecycle helpers.",
        } or nil
    end

    if ContainsAny(text, { "wago backup", "profile backup confirmed", "backup confirmed" }) then
        local clear = ContainsAny(text, { "clear", "reset", "unconfirm", "not confirmed" })
        local action = Registry and Registry:GetAction("confirm_wago_backup")
        return action and {
            kind = "action",
            action = action,
            args = { confirmed = not clear },
            label = clear and "Clear Wago backup confirmation" or "Confirm Wago backup",
            summary = "Updates the Dashboard Wago backup checklist state for the active profile.",
        } or nil
    end

    if ContainsAny(text, { "recovery tools", "display recovery", "recover menu", "reset tools", "dashboard recovery" }) then
        local action = Registry and Registry:GetAction("open_recovery_tools")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open recovery tools",
            summary = "Opens the Dashboard recovery area.",
        } or nil
    end

    if ContainsAny(text, { "scaling tools", "dashboard scaling", "scale tools", "ui scale tools", "open scaling" }) then
        local action = Registry and Registry:GetAction("open_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { panel = "scaling" },
            label = "Open scaling tools",
            summary = "Opens the Dashboard scaling area.",
        } or nil
    end

    if ContainsAny(text, { "changelog", "change log", "release notes", "latest changes", "build notes" }) then
        local action = Registry and Registry:GetAction("open_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { panel = "changelog" },
            label = "Open changelog",
            summary = "Opens the Dashboard changelog.",
        } or nil
    end

    local link = SupportLinkForText(text)
    if link and ContainsAny(text, { "copy", "open", "link", "support", "join", "repo", "repository", "donate" }) then
        local action = Registry and Registry:GetAction("copy_support_link")
        return action and {
            kind = "action",
            action = action,
            args = { link = link },
            label = "Copy support link",
            summary = "Opens a copyable MSUF support link.",
        } or nil
    end

    if ContainsAny(text, { "support links", "support msuf", "donate links", "development links" }) then
        local action = Registry and Registry:GetAction("support_links_summary")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show support links",
            summary = "Lists MSUF support links.",
        } or nil
    end
    return nil
end

local function GlobalScalePresetForText(text)
    if ContainsAny(text, { "1080p", "1080" }) then return "1080p" end
    if ContainsAny(text, { "1440p", "1440" }) then return "1440p" end
    if ContainsAny(text, { "4k", "2160p", "2160" }) then return "4k" end
    if ContainsAny(text, { "pixel perfect", "pixel" }) then return "pixel" end
    if ContainsAny(text, { "turn off", "disable", "off", "auto" }) then return "off" end
    return nil
end

local function ParsePresetWorkflow(text)
    if not ContainsAny(text, { "preset", "global ui scale", "wow ui scale", "global scale", "scale preset" }) then return nil end
    if not ContainsAny(text, { "global ui scale", "wow ui scale", "global scale", "scale preset" }) then return nil end
    local preset = GlobalScalePresetForText(text)
    if not preset then return nil end
    local action = Registry and Registry:GetAction("apply_global_scale_preset")
    return action and {
        kind = "action",
        action = action,
        args = { preset = preset },
        label = "Apply global UI scale preset",
        summary = "Applies one of the Dashboard global WoW UI scale presets.",
    } or nil
end

local function ParseScopedOverrideReset(text)
    local font = ContainsAny(text, { "font", "fonts", "text style", "name color", "text color" })
    local bars = ContainsAny(text, { "bars", "bar", "bar texture", "global bars", "gradient", "absorb", "highlight border", "dispel overlay", "aggro border", "purge border" })
    if not font and not bars then return nil end
    local reset = ContainsAny(text, {
        "reset", "clear", "restore", "default", "defaults", "follow shared", "use shared",
        "remove override", "remove custom", "disable custom", "turn off custom",
    })
    if not reset then return nil end
    local all = ContainsAny(text, {
        "all overrides", "every override", "all custom", "all scopes",
        "all bar overrides", "all bars overrides", "all global bar overrides", "all global bars overrides",
        "all font overrides", "all fonts overrides", "all global font overrides", "all global fonts overrides",
        "every bar override", "every bars override", "every font override", "every fonts override",
    })
    local scope = DetectGlobalScope(text)
    if not all and (not scope or scope == "shared") then return nil end
    local actionKey
    if font and not bars then
        actionKey = all and "reset_all_scoped_global_font_overrides" or "reset_scoped_global_font_override"
    elseif bars and not font then
        actionKey = all and "reset_all_scoped_global_bars_overrides" or "reset_scoped_global_bars_override"
    else
        return nil
    end
    local action = Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = all == true,
        label = all and "Reset all scoped overrides" or "Reset scoped override",
        summary = "Uses the same scoped override flags as Global Style.",
    } or nil
end

local function ParseClassPowerAction(text)
    if not ContainsAny(text, { "quick setup", "quicksetup", "setup" }) then return nil end
    if not ContainsAny(text, CLASS_POWER_TERMS) then return nil end
    local action = Registry and Registry:GetAction("class_power_quick_setup")
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = true,
        label = "Quick setup class bar",
        summary = "Runs the Class Resources quick setup workflow.",
    } or nil
end

local GAMEPLAY_ROOT_TOGGLES = {
    {
        key = "gameplay.enableCombatTimer",
        label = "Combat Timer",
        terms = { "combat timer" },
        details = { "anchor", "attach", "size", "font", "text size", "lock", "locked", "click through", "click-through", "x", "y", "offset", "move", "color", "colors" },
    },
    {
        key = "gameplay.enableCombatStateText",
        label = "Combat Enter Leave Text",
        terms = { "combat state", "combat enter leave", "combat enter", "combat leave" },
        details = { "size", "font", "duration", "lock", "locked", "x", "y", "offset", "move", "color", "colors", "sync" },
    },
    {
        key = "gameplay.enablePlayerTotems",
        label = "Blizzard Totem Frame",
        terms = { "totem frame", "totemframe", "blizzard totem", "statue frame" },
        details = { "icon", "size", "x", "y", "offset", "anchor", "from", "to", "preview", "reset", "layout", "move" },
    },
    {
        key = "gameplay.enableFirstDanceTimer",
        label = "First Dance Tracker",
        terms = { "first dance" },
        details = { "icon", "ready", "size", "lock", "locked", "click through", "click-through", "x", "y", "offset", "move" },
    },
    {
        key = "gameplay.enableCombatCrosshair",
        label = "Combat Crosshair",
        terms = { "combat crosshair", "crosshair", "fadenkreuz" },
        details = { "range", "melee", "color", "colors", "spell", "size", "thickness", "x", "y", "offset", "move", "class", "spec" },
    },
}

local function ParseGameplayRootToggle(text)
    local value = DetectBoolean(text)
    if value == nil then return nil end
    for i = 1, #GAMEPLAY_ROOT_TOGGLES do
        local item = GAMEPLAY_ROOT_TOGGLES[i]
        if ContainsAny(text, item.terms) and not ContainsAny(text, item.details) then
            local setting = Registry and Registry:GetSetting(item.key)
            return setting and {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = item.label,
                summary = "Toggles a Gameplay setting.",
            } or nil
        end
    end
    return nil
end

local function ParseGameplayAction(text, raw)
    if ContainsAny(text, { "crosshair", "fadenkreuz", "melee range spell", "range check spell" }) and ContainsAny(text, { "spell", "range check" }) then
        local rawText = tostring(raw or "")
        local value
        if ContainsAny(text, { "clear", "reset", "none", "no spell" }) then
            value = "0"
        else
            value = rawText:match("([Ss][Pp][Ee][Ll][Ll]:%d+)") or rawText:match("#%s*(%d+)") or rawText:match("(%d%d+)")
            if not value then
                local patterns = {
                    "[Ss]et%s+[Cc]rosshair%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Ss]et%s+[Cc]rosshair%s+.+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Cc]hange%s+[Cc]rosshair%s+.+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Ss]et%s+[Mm]elee%s+[Rr]ange%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Ss]et%s+.+[Mm]elee%s+[Rr]ange%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Cc]hange%s+.+[Mm]elee%s+[Rr]ange%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Uu]se%s+(.+)%s+[Ff]or%s+.+[Cc]rosshair",
                    "[Uu]se%s+(.+)%s+[Ff]or%s+.+[Mm]elee%s+[Rr]ange",
                }
                for i = 1, #patterns do
                    value = rawText:match(patterns[i])
                    value = CleanProfileName(value)
                    if value then break end
                end
            end
        end
        if value then
            local action = Registry and Registry:GetAction("set_crosshair_melee_spell")
            return action and {
                kind = "action",
                action = action,
                args = { value = value },
                label = "Set Crosshair Melee Range Spell",
                summary = "Resolves a spell ID, spell link, or spell name for the Combat Crosshair range check.",
            } or nil
        end
    end
    if ContainsAny(text, { "preview", "test" }) and ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame" }) then
        local action = Registry and Registry:GetAction("preview_player_totems")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Preview Totem Frame",
            summary = "Toggles the TotemFrame preview.",
        } or nil
    end
    if ContainsAny(text, { "reset", "restore", "default", "defaults" }) and ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame" }) then
        local action = Registry and Registry:GetAction("reset_player_totems_layout")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset Totem Frame Layout",
            summary = "Restores the TotemFrame layout defaults.",
        } or nil
    end
    return nil
end

local function ParseGlobalBarsAction(text)
    if ContainsAny(text, { "dispel test type", "dispel border test type", "dispel border preview type" }) then
        local value
        if ContainsAny(text, { "curse" }) then value = "Curse"
        elseif ContainsAny(text, { "disease" }) then value = "Disease"
        elseif ContainsAny(text, { "poison" }) then value = "Poison"
        elseif ContainsAny(text, { "bleed" }) then value = "Bleed"
        elseif ContainsAny(text, { "magic" }) then value = "Magic" end
        local action = Registry and Registry:GetAction("set_dispel_border_test_type")
        return action and {
            kind = "action",
            action = action,
            args = { value = value or "Magic" },
            label = "Set dispel border test type",
            summary = "Changes the transient dispel border preview type.",
        } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "absorb bar", "absorb bars", "prediction bars", "heal absorb" }) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) },
            label = "Toggle absorb bar test",
            summary = "Toggles the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, { "clear", "stop", "disable", "off" }) and ContainsAny(text, { "absorb test", "prediction bar test" }) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = false },
            label = "Disable absorb bar test",
            summary = "Turns off the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "aggro border", "threat border" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "aggro", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test aggro border", summary = "Toggles the aggro border test." } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "dispel border", "dispellable border" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "dispel", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test dispel border", summary = "Toggles the dispel border test." } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "purge border", "purgeable border" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "purge", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test purge border", summary = "Toggles the purge border test." } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "boss target border", "boss target highlight" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "bossTarget", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test boss target border", summary = "Toggles the boss target border test." } or nil
    end
    return nil
end

local function ParseDarkModeBrightnessShortcut(text)
    if not ContainsAny(text, { "dark mode", "dark bars", "dark bar", "dark mode bar color", "dark bar brightness" }) then return nil end
    if not ContainsAny(text, {
        "lighter", "brighter", "brighten", "heller",
        "darker", "darken", "dunkler", "super dark", "very dark", "black", "almost black",
        "brightness", "bar color",
    }) then
        return nil
    end
    local setting = Registry and Registry:GetSetting("general.darkBarGray")
    if not setting then return nil end

    local value
    local relativeDelta
    local amount = FirstNumber(text)
    if amount ~= nil and ContainsAny(text, { "to", "set", "value" }) then
        value = amount > 1 and (amount / 100) or amount
    elseif ContainsAny(text, { "super dark", "very dark", "almost black", "black" }) then
        value = 0.01
    elseif ContainsAny(text, { "lighter", "brighter", "brighten", "heller" }) then
        local fallback = ContainsAny(text, { "bit", "a bit", "slightly", "little", "etwas" }) and 0.03 or 0.08
        relativeDelta = amount and (amount > 1 and amount / 100 or amount) or fallback
    elseif ContainsAny(text, { "darker", "darken", "dunkler" }) then
        local fallback = ContainsAny(text, { "bit", "a bit", "slightly", "little", "etwas" }) and 0.03 or 0.08
        relativeDelta = -((amount and (amount > 1 and amount / 100 or amount)) or fallback)
    end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Set dark mode bar color",
        summary = "Adjusts the real Colors > Unitframe Global Coloring dark-mode bar color slider.",
    }
end

local function ParseCastbarPreviewAction(text)
    if not ContainsAny(text, { "test", "preview", "show preview" }) then return nil end
    if not ContainsAny(text, { "castbar", "cast bar" }) then return nil end
    local action = Registry and Registry:GetAction("preview_castbar")
    if not action then return nil end
    local units = DetectUnits(text)
    local unit = units[1] or "player"
    local kind = "normal"
    if ContainsAny(text, { "channel", "channeled", "channelled" }) then
        kind = "channel"
    elseif ContainsAny(text, { "empowered", "empower", "evoker" }) then
        kind = "empowered"
    end
    return {
        kind = "action",
        action = action,
        args = {
            unit = unit,
            kind = kind,
            interrupt = ContainsAny(text, { "interrupt", "interrupted", "shake" }),
        },
        label = "Preview castbar",
        summary = "Opens the Castbar page and selects the requested transient preview.",
    }
end

local CASTBAR_GLOBAL_BOOLEAN_DETAILS = {
    { key = "general.castbarShowChannelTicks", terms = { "channel ticks", "channel tick lines", "castbar ticks", "tick lines" } },
    { key = "general.castbarShowGlow", terms = { "glow", "glow effect" } },
    { key = "general.castbarShowSpark", terms = { "spark", "castbar spark" } },
    { key = "general.castbarSparkOverflow", terms = { "spark overflow", "spark beyond bar" } },
    { key = "general.castbarShowLatency", terms = { "latency", "latency indicator" } },
    { key = "general.castbarUnifiedDirection", terms = { "unified direction", "unified fill direction", "same fill direction" } },
    { key = "general.castbarOpositeDirectionTarget", terms = { "target opposite direction", "opposite target direction", "target opposite fill direction" } },
    { key = "general.empowerColorStages", terms = { "empower color stages", "empowered stage colors", "empower stage colors" } },
    { key = "general.empowerStageBlink", terms = { "empower stage blink", "empowered stage blink", "stage blink" } },
}

local function ParseCastbarGlobalDetail(text)
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    for i = 1, #CASTBAR_GLOBAL_BOOLEAN_DETAILS do
        local spec = CASTBAR_GLOBAL_BOOLEAN_DETAILS[i]
        if ContainsAny(text, spec.terms) then
            local setting = Registry and Registry:GetSetting(spec.key)
            return setting and {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Castbar detail",
                summary = "Changes a global Castbar detail setting without toggling the unit castbar root.",
            } or nil
        end
    end
    return nil
end

local function ParseGuidedSetup(text)
    if not ContainsAny(text, { "help me build", "guided setup", "setup", "build a clean", "clean layout", "rogue layout", "layout bauen", "setup hilfe" }) then return nil end
    local action = Registry and Registry:GetAction("guided_setup")
    return action and {
        kind = "action",
        action = action,
        args = { style = text },
        label = "Guided setup",
        summary = "Starts a deterministic setup workflow.",
    } or nil
end

local function ParseGuidedSetupFollowup(text, ctx)
    local active = ctx and type(ctx.guidedSetup) == "table"
    local explicit = ContainsAny(text, {
        "cancel setup", "stop setup", "abort setup", "setup cancel",
        "finish setup", "done setup", "setup done", "complete setup", "setup complete",
        "skip setup", "skip setup step", "setup skip",
        "next setup", "next setup step", "setup next", "continue setup",
        "back setup", "back setup step", "setup back", "previous setup", "previous setup step", "setup previous",
        "show setup", "show setup step", "repeat setup", "current setup step", "setup status",
    })
    if not active and not explicit then return nil end
    local command
    if ContainsAny(text, { "cancel setup", "stop setup", "abort setup", "setup cancel" }) or (active and HasPhrase(text, "cancel")) then
        command = "cancel"
    elseif ContainsAny(text, { "finish setup", "done setup", "setup done", "complete setup", "setup complete" }) or (active and HasPhrase(text, "done")) then
        command = "finish"
    elseif ContainsAny(text, { "skip setup", "skip setup step", "setup skip" }) or (active and HasPhrase(text, "skip")) then
        command = "skip"
    elseif ContainsAny(text, { "next setup", "next setup step", "setup next", "continue setup" }) or (active and ContainsAny(text, { "next", "continue" })) then
        command = "next"
    elseif ContainsAny(text, { "back setup", "back setup step", "setup back", "previous setup", "previous setup step", "setup previous" }) or (active and ContainsAny(text, { "back", "previous" })) then
        command = "back"
    elseif ContainsAny(text, { "show setup", "show setup step", "repeat setup", "current setup step", "setup status" }) then
        command = "show"
    end
    if not command then return nil end
    local action = Registry and Registry:GetAction("guided_setup_step")
    return action and {
        kind = "action",
        action = action,
        args = { command = command },
        label = "Guided setup step",
        summary = "Continues the active deterministic setup workflow.",
    } or nil
end

local function BuildChanges(settings, value, relativeDelta, direction)
    local changes = {}
    for i = 1, #settings do
        changes[#changes + 1] = {
            setting = settings[i],
            value = value,
            relativeDelta = relativeDelta,
            direction = direction,
        }
    end
    return changes
end

local function ParseUnsupportedDetailShortcut(text)
    if ContainsAny(text, { "combat timer alpha", "combat timer opacity", "combat timer transparency" }) then
        return {
            kind = "unknown",
            text = "Combat Timer alpha is not exposed by the current MSUF UI/DB. The Assistant can change real Combat Timer controls like enable, size, position, anchor, lock, and colors.",
            status = "failed",
        }
    end
    if ContainsAny(text, { "hp text anchor", "health text anchor", "power text anchor", "mana text anchor" }) then
        return {
            kind = "unknown",
            text = "HP/Power text does not have a separate anchor dropdown in the current MSUF UI. Use the left/center/right text slots and X/Y offsets instead.",
            status = "failed",
        }
    end
    return nil
end

local function CurrentPageUnit()
    local page = M and M.activeKey
    if type(page) ~= "string" then return nil end
    for i = 1, #ALL_UNITFRAMES do
        local unit = ALL_UNITFRAMES[i]
        if UnitPageKey(unit) == page then return unit end
    end
    return nil
end

local function DetailUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    if #units > 0 then return units, false end
    local pageUnit = CurrentPageUnit()
    if pageUnit then return { pageUnit }, false end
    return {}, true
end

local function BuildUnitDetailChoices(attr, value, relativeDelta, direction)
    local settings = {}
    for i = 1, #ALL_UNITFRAMES do
        local setting = Registry and Registry:GetSetting(tostring(ALL_UNITFRAMES[i]) .. "." .. attr)
        if setting then settings[#settings + 1] = setting end
    end
    return {
        kind = "ambiguous",
        choices = BuildChanges(settings, value, relativeDelta, direction),
        label = "Multiple matching unitframe detail settings",
    }
end

local function ParsePortraitDetailShortcut(text)
    if not ContainsAny(text, { "portrait" }) then return nil end
    if ContainsAny(text, { "color", "colour", "farbe", "reset" }) then return nil end
    if ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) and DetectDirection(text, {}) then return nil end

    local attr
    local value
    local relativeDelta
    local direction

    if ContainsAny(text, { "border thickness", "border size", "border thicker", "border thinner", "thicker", "thinner", "dicker", "duenner" }) then
        attr = "portraitBorderThickness"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
        if relativeDelta == nil then value = FirstNumber(text) end
    elseif ContainsAny(text, { "size", "size override", "bigger", "smaller", "larger", "groesser", "kleiner" }) then
        attr = "portraitSizeOverride"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 4)
        if relativeDelta == nil then value = FirstNumber(text) end
    elseif ContainsAny(text, { "border" }) then
        attr = "portraitBorderStyle"
        if ContainsAny(text, { "off", "disable", "disabled", "hide", "none", "no border", "aus", "deaktivieren" }) then
            value = "NONE"
        elseif ContainsAny(text, { "on", "enable", "enabled", "show", "solid", "an", "aktivieren" }) then
            value = "SOLID"
        elseif ContainsAny(text, { "class color", "class" }) then
            value = "CLASS_COLOR"
        elseif ContainsAny(text, { "reaction" }) then
            value = "REACTION"
        elseif ContainsAny(text, { "custom" }) then
            value = "CUSTOM"
        end
    else
        attr = "portraitMode"
        if ContainsAny(text, { "off", "disable", "disabled", "hide", "aus", "deaktivieren" }) then
            value = "OFF"
        elseif ContainsAny(text, { "right" }) then
            value = "RIGHT"
        elseif ContainsAny(text, { "on", "enable", "enabled", "show", "left", "an", "aktivieren" }) then
            value = "LEFT"
        end
    end

    if not attr or (value == nil and relativeDelta == nil) then return nil end
    local units, ambiguous = DetailUnitsOrCurrentPage(text)
    if ambiguous then return BuildUnitDetailChoices(attr, value, relativeDelta, direction) end
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Portrait detail",
        summary = "Changes a registered portrait detail control.",
    }
end

local DETAIL_MOVE_SPECS = {
    { terms = { "portrait" }, x = "portraitOffsetX", y = "portraitOffsetY", label = "Move portrait" },
    { terms = { "name text", "unit name", "name" }, x = "nameOffsetX", y = "nameOffsetY", label = "Move name text" },
    { terms = { "hp text", "health text", "health value" }, x = "hpOffsetX", y = "hpOffsetY", label = "Move HP text" },
    { terms = { "power text", "mana text", "power value", "mana value" }, x = "powerOffsetX", y = "powerOffsetY", label = "Move power text" },
}

local function ParseUnitDetailMove(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local spec
    for i = 1, #DETAIL_MOVE_SPECS do
        if ContainsAny(text, DETAIL_MOVE_SPECS[i].terms) then
            spec = DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local attr = (direction == "left" or direction == "right") and spec.x or spec.y
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Moves a unitframe detail control by pixels.",
    }
end

local function OutlineScopeSettingForText(text)
    local explicitScope = DetectGlobalScope(text)
    local scope = explicitScope
    if not scope or scope == "shared" then
        local pageUnit = CurrentPageUnit()
        if pageUnit then scope = pageUnit end
    end
    if scope and scope ~= "shared" then
        local scoped = Registry and Registry:GetSetting("barScope." .. tostring(scope) .. ".barOutlineThickness")
        if scoped then return scoped, scope end
    end
    return Registry and Registry:GetSetting("bars.barOutlineThickness"), "shared"
end

local function ParseBorderThicknessShortcut(text)
    if not ContainsAny(text, { "border", "outline" }) then return nil end
    if ContainsAny(text, { "portrait", "castbar", "cast bar", "class power", "class resource" }) then return nil end
    if ContainsAny(text, { "color", "colour", "farbe", "reset" }) then return nil end
    if ContainsAny(text, { "aggro", "threat", "dispel", "dispellable", "purge", "purgeable", "boss target", "highlight" }) then return nil end

    local explicitDetail = ContainsAny(text, {
        "frame outline", "frame border", "bar outline", "bar border", "border outline", "outline border",
        "outline thickness", "border thickness", "outline size", "border size", "outline width", "border width",
        "outline thicker", "outline thinner", "border thicker", "border thinner",
        "thicker", "thinner", "bigger", "larger", "smaller", "dicker", "duenner",
    })
    local toggleIntent = DetectBoolean(text) ~= nil
    local numberIntent = FirstNumber(text) ~= nil
    if not (explicitDetail or toggleIntent or numberIntent) then return nil end

    local setting = OutlineScopeSettingForText(text)
    if not setting then return nil end

    local value
    local relativeDelta
    local bool = DetectBoolean(text)
    if bool ~= nil and not numberIntent and not ContainsAny(text, { "thicker", "thinner", "bigger", "larger", "smaller", "increase", "decrease", "dicker", "duenner" }) then
        value = bool and 1 or 0
    else
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
        if relativeDelta == nil then value = FirstNumber(text) end
    end
    if value == nil and relativeDelta == nil then return nil end

    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = setting.label or "Frame outline thickness",
        summary = "Changes the registered frame/bar outline thickness control instead of toggling the whole unit frame.",
    }
end

local function ParseUnitDetailOffsetShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(text, { "offset" }) then return nil end
    if DetectDirection(text, {}) then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end
    local spec
    for i = 1, #DETAIL_MOVE_SPECS do
        if ContainsAny(text, DETAIL_MOVE_SPECS[i].terms) then
            spec = DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            units = ALL_UNITFRAMES
        end
    end
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local sx = Registry and Registry:GetSetting(unit .. "." .. spec.x)
        local sy = Registry and Registry:GetSetting(unit .. "." .. spec.y)
        if sx then changes[#changes + 1] = { setting = sx, value = value, direction = "x" } end
        if sy then changes[#changes + 1] = { setting = sy, value = value, direction = "y" } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which " .. tostring(spec.label or "detail") .. " offset should I set?",
        summary = "The command names an offset but not X/Y or a movement direction.",
    }
end

local CASTBAR_DETAIL_PREFIXES = {
    player = "castbarPlayer",
    target = "castbarTarget",
    focus = "castbarFocus",
    boss = "bossCast",
}

local function CastbarDetailUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    local filtered = {}
    for i = 1, #units do
        local unit = units[i]
        if CASTBAR_DETAIL_PREFIXES[unit] then filtered[#filtered + 1] = unit end
    end
    if #filtered > 0 then return filtered end
    local pageUnit = CurrentPageUnit()
    if pageUnit and CASTBAR_DETAIL_PREFIXES[pageUnit] then return { pageUnit } end
    return { "player", "target", "focus", "boss" }
end

local function ParseCastbarTextMoveShortcut(text)
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local field
    local label
    if ContainsAny(text, { "time text", "castbar time", "cast time", "timer", "time" }) then
        field = (direction == "left" or direction == "right") and "TimeOffsetX" or "TimeOffsetY"
        label = "Move castbar time text"
    elseif ContainsAny(text, { "spell name", "spell text", "castbar text", "castbar name", "text" }) then
        field = (direction == "left" or direction == "right") and "TextOffsetX" or "TextOffsetY"
        label = "Move castbar spell text"
    else
        return nil
    end
    local amount = FirstNumber(text) or 5
    if direction == "left" or direction == "down" then amount = -amount end
    local units = CastbarDetailUnitsOrCurrentPage(text)
    local changes = {}
    for i = 1, #units do
        local prefix = CASTBAR_DETAIL_PREFIXES[units[i]]
        local setting = prefix and Registry and Registry:GetSetting("general." .. prefix .. field)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #DetectUnits(text) == 0 and not CurrentPageUnit() then
        return { kind = "ambiguous", choices = changes, label = "Which castbar text should I move?" }
    end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        summary = "Moves a registered castbar text detail control by pixels.",
    }
end

local function ParseUnitOpacityShortcut(text)
    if not ContainsAny(text, { "alpha", "opacity", "transparency", "transparent", "opaque" }) then return nil end
    if ContainsAny(text, { "range fade", "in combat", "out of combat", "outside combat", "sync", "affects", "fade target", "preserve hp" }) then return nil end
    local relativeDelta
    if ContainsAny(text, { "more transparent", "more transparency", "more see through", "transparenter" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, { "less transparent", "less transparency", "more opaque", "opaquer" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
    else
        relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
    end
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            return {
                kind = "unknown",
                text = "Which unitframe alpha should I change? Try 'set player alpha to 50' or open a unit page and say 'set alpha to 50'.",
                status = "failed",
            }
        end
    end
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local inCombat = Registry and Registry:GetSetting(unit .. ".alphaInCombat")
        local outCombat = Registry and Registry:GetSetting(unit .. ".alphaOutOfCombat")
        if inCombat then changes[#changes + 1] = { setting = inCombat, value = value, relativeDelta = relativeDelta } end
        if outCombat then changes[#changes + 1] = { setting = outCombat, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set unit opacity",
        summary = "Sets both in-combat and out-of-combat opacity for the requested unitframe.",
    }
end

local function GroupColorModeScopes(text)
    local scopes = {}
    local explicitGroupGeneric = ContainsAny(text, { "group frames", "group frame", "gruppenframes", "groups" })
    local explicitNamed = false
    if ContainsAny(text, { "party", "party frame", "party frames", "partyframe" }) then AddUnique(scopes, "party"); explicitNamed = true end
    if ContainsAny(text, { "mythic raid", "mythicraid", "mythic raid frame", "mythic raid frames", "mythicraidframe" }) then AddUnique(scopes, "mythicraid"); explicitNamed = true end
    if ContainsAny(text, { "raid", "raid frame", "raid frames", "raidframe" }) and not ContainsAny(text, { "mythic raid", "mythicraid", "mythicraidframe" }) then
        AddUnique(scopes, "raid")
        explicitNamed = true
    end
    if not explicitNamed and explicitGroupGeneric then
        return { "party", "raid", "mythicraid" }
    end
    if #scopes == 0 then
        local detected = DetectGroups(text)
        for i = 1, #detected do AddUnique(scopes, detected[i]) end
    end
    return scopes
end

local function GroupBarColorModeForText(text)
    local bool = DetectBoolean(text)
    if ContainsAny(text, { "class color", "class colors", "class colored", "class mode" }) then
        return bool == false and "GLOBAL" or "CLASS"
    end
    if ContainsAny(text, { "gradient", "health gradient" }) then return bool == false and "GLOBAL" or "GRADIENT" end
    if ContainsAny(text, { "custom", "manual" }) then return bool == false and "GLOBAL" or "CUSTOM" end
    if ContainsAny(text, { "dark mode", "dark bars", "dark" }) then return bool == false and "GLOBAL" or "dark" end
    if ContainsAny(text, { "unified", "unified color", "unified bars" }) then return bool == false and "GLOBAL" or "unified" end
    if ContainsAny(text, { "global", "global style", "inherit", "default" }) then return "GLOBAL" end
    return nil
end

local function ParseGroupFrameColorMode(text)
    if not ContainsAny(text, {
        "group frames", "group frame", "gruppenframes", "party", "party frame", "party frames", "partyframe",
        "raid", "raid frame", "raid frames", "raidframe", "mythic raid", "mythicraid",
    }) then
        return nil
    end
    if not ContainsAny(text, {
        "bar color mode", "health bar color mode", "class color mode", "health color mode",
        "group bar style", "bar mode", "class colored health", "class color health",
    }) then
        return nil
    end
    local value = GroupBarColorModeForText(text)
    if not value then return nil end
    local scopes = GroupColorModeScopes(text)
    if #scopes == 0 then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".gfBarMode")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group-frame bar color mode",
        summary = "Changes the real Group Frames > Health & Text Bar Color Mode instead of the global unitframe bar mode.",
    }
end

local MENU_SELECTOR_VERBS = {
    "select", "choose", "pick", "open", "show", "switch to", "go to", "focus", "edit",
}

local function HasMenuSelectorVerb(text)
    return ContainsAny(text, MENU_SELECTOR_VERBS)
end

local function MenuSelectorAction(args, label, summary)
    local action = Registry and Registry:GetAction("set_menu_selector_state")
    return action and {
        kind = "action",
        action = action,
        args = args,
        label = label or "Set menu selector state",
        summary = summary or "Selects a visible Menu2 tab, dropdown entry, or editor slot without changing the underlying setting value.",
    } or nil
end

local function SelectorUnit(text)
    local units = DetectUnits(text)
    return units[1] or CurrentPageUnit()
end

local function SelectorGroupScope(text)
    local groups = DetectGroups(text)
    if groups[1] then return groups[1] end
    if M and (M.gfScope == "party" or M.gfScope == "raid" or M.gfScope == "mythicraid") then return M.gfScope end
    return "party"
end

local function TextSelectorTab(text)
    if ContainsAny(text, { "advanced text tab", "advanced text", "text advanced", "text layers", "advanced tab" }) then return "advanced" end
    if ContainsAny(text, { "power text tab", "power text", "mana text", "power tab", "mana tab", "power", "mana" }) then return "power" end
    if ContainsAny(text, { "hp text tab", "health text tab", "hp text", "health text", "hp tab", "health tab", "hp", "health" }) then return "hp" end
    if ContainsAny(text, { "name text tab", "name text", "name tab", "name" }) then return "name" end
    return nil
end

local function TextSelectorSlot(text)
    if ContainsAny(text, { "left slot", "slot left", "left text slot" }) or (HasPhrase(text, "left") and ContainsAny(text, { "slot", "text slot" })) then return "left" end
    if ContainsAny(text, { "center slot", "centre slot", "middle slot", "slot center", "slot centre", "slot middle", "center text slot", "centre text slot", "middle text slot" })
        or ((HasPhrase(text, "center") or HasPhrase(text, "centre") or HasPhrase(text, "middle")) and ContainsAny(text, { "slot", "text slot" }))
    then
        return "center"
    end
    if ContainsAny(text, { "right slot", "slot right", "right text slot" }) or (HasPhrase(text, "right") and ContainsAny(text, { "slot", "text slot" })) then return "right" end
    return nil
end

local function TextSelectorIntent(text, tab, slot)
    if ContainsAny(text, {
        "text area", "text tab", "text tabs", "text editor", "text slot", "slot selector", "slot dropdown",
        "selected slot", "left slot", "center slot", "centre slot", "right slot",
    }) then
        return true
    end
    return tab and ContainsAny(text, { "name text", "hp text", "health text", "power text", "mana text" }) and (HasPhrase(text, "tab") or slot ~= nil)
end

local function TextMoveTogetherIntent(text)
    return ContainsAny(text, {
        "move text as one group", "move as one group", "text as one group",
        "move text together", "text move together", "move together",
        "move text per slot", "text per slot", "per slot", "selected slot mode",
        "individual slot", "individual slots", "separate slot", "separate slots",
        "move text separately", "text separately",
    })
end

local function TextMoveTogetherValue(text)
    if ContainsAny(text, {
        "per slot", "selected slot mode", "individual slot", "individual slots",
        "separate slot", "separate slots", "separately", "text separately",
    }) then
        return false
    end
    local value = DetectBoolean(text)
    if value ~= nil then return value end
    return true
end

local function StatusSelectorTab(text)
    if ContainsAny(text, { "advanced status tab", "advanced status icon tab", "advanced indicator tab", "advanced status controls", "advanced status" }) then return "advanced" end
    if ContainsAny(text, { "basic status tab", "basic status icon tab", "basic indicator tab", "basic status controls", "basic status" }) then return "basic" end
    return nil
end

local function StatusSelectorIntent(text)
    if ContainsAny(text, {
        "status tab", "status icon tab", "status indicator tab", "indicator tab",
        "status selector", "status dropdown", "indicator selector", "indicator dropdown",
        "status controls", "status icon controls", "selected indicator",
    }) then
        return true
    end
    return ContainsAny(text, { "indicator", "status icon" })
end

local function ParseMenuSelectorState(text)
    if TextMoveTogetherIntent(text) then
        local textTab = TextSelectorTab(text)
        if textTab == "hp" or textTab == "power" then
            local groups = DetectGroups(text)
            if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
                return MenuSelectorAction({
                    selector = "group_text_move_together",
                    scope = groups[1] or SelectorGroupScope(text),
                    tab = textTab,
                    value = TextMoveTogetherValue(text),
                }, "Set group text move mode")
            end
            local unit = SelectorUnit(text)
            if unit then
                return MenuSelectorAction({
                    selector = "unit_text_move_together",
                    unit = unit,
                    tab = textTab,
                    value = TextMoveTogetherValue(text),
                }, "Set unit text move mode")
            end
        end
    end

    if not HasMenuSelectorVerb(text) then return nil end

    if ContainsAny(text, { "class power color token", "class resource color token", "class power token", "class resource token" }) then
        local token = ClassPowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "classPower", token = token }, "Select class resource color token")
        end
    end
    if ContainsAny(text, { "power color token", "power token", "power type", "resource type", "resource color token" })
        and not ContainsAny(text, { "class power", "class resource", "combo point", "combo points" })
    then
        local token = PowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "power", token = token }, "Select power color token")
        end
    end

    local textTab = TextSelectorTab(text)
    local textSlot = TextSelectorSlot(text)
    if textTab and TextSelectorIntent(text, textTab, textSlot) then
        local groups = DetectGroups(text)
        if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
            return MenuSelectorAction({
                selector = "group_text",
                scope = groups[1] or SelectorGroupScope(text),
                tab = textTab,
                slot = textSlot,
            }, "Select group text editor state")
        end
        local unit = SelectorUnit(text)
        if unit then
            return MenuSelectorAction({
                selector = "unit_text",
                unit = unit,
                tab = textTab,
                slot = textSlot,
            }, "Select unit text editor state")
        end
    end

    if ContainsAny(text, { "spell indicator selector", "spell indicator dropdown", "spell indicator spec", "tracked spell selector", "tracked spells selector", "tracked spell", "multi spec entry", "multi-spec entry" }) then
        local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(text) or nil
        local aura, resolvedSpec = A.ResolveGroupSpellAura and A.ResolveGroupSpellAura(spec, text) or nil
        spec = spec or resolvedSpec
        if spec or aura then
            return MenuSelectorAction({
                selector = "group_spell",
                scope = SelectorGroupScope(text),
                spec = spec,
                aura = aura,
                text = text,
            }, "Select group spell indicator editor state")
        end
    end

    if ContainsAny(text, { "corner editor slot", "editor slot", "corner slot", "custom spell editor" }) then
        local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
        if slot then
            return MenuSelectorAction({
                selector = "group_corner",
                scope = SelectorGroupScope(text),
                slot = slot.key or slot.value or text,
                text = text,
            }, "Select group corner editor slot")
        end
    end

    local statusTab = StatusSelectorTab(text)
    local statusIntent = StatusSelectorIntent(text)
    if statusIntent then
        local groups = DetectGroups(text)
        local groupStatusIcon = GroupStatusIconForText(text)
        if groups[1] or ContainsAny(text, { "group status", "group indicator", "party indicator", "raid indicator", "mythic raid indicator" }) then
            if statusTab or groupStatusIcon then
                return MenuSelectorAction({
                    selector = "group_status",
                    scope = groups[1] or SelectorGroupScope(text),
                    tab = statusTab,
                    icon = groupStatusIcon,
                    text = text,
                }, "Select group status icon editor state")
            end
        end

        local unit = SelectorUnit(text)
        local unitStatus = unit and A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text) or nil
        if unit and (statusTab or unitStatus) then
            return MenuSelectorAction({
                selector = "unit_status",
                unit = unit,
                tab = statusTab,
                status = unitStatus and unitStatus.value,
                text = text,
            }, "Select unit status editor state")
        end

        if groupStatusIcon then
            return MenuSelectorAction({
                selector = "group_status",
                scope = SelectorGroupScope(text),
                icon = groupStatusIcon,
                text = text,
            }, "Select group status icon editor state")
        end
    end

    return nil
end

local function ContextUnits(ctx)
    local units = {}
    if ctx and type(ctx.lastUnit) == "string" then units[#units + 1] = ctx.lastUnit end
    return units
end

local function BuildFollowup(text, ctx)
    if not (ctx and type(ctx.lastChangeBundle) == "table") then return nil end
    if not ContainsAny(text, { "too", "also", "same", "auch", "genauso", "das auch", "same for" }) then return nil end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local changes = {}
    for i = 1, #ctx.lastChangeBundle do
        local prev = ctx.lastChangeBundle[i]
        for j = 1, #units do
            local found = Registry:FindSettings({ unit = units[j], frameType = prev.frameType, attribute = prev.attribute })
            if found[1] then
                changes[#changes + 1] = { setting = found[1], value = prev.value }
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Apply previous change to another frame",
        summary = "Uses the last Assistant change as context.",
    }
end

local function BuildBooleanCorrection(text, ctx)
    if not (ctx and type(ctx.lastSetting) == "string") then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    if not ContainsAny(text, {
        "again", "wieder", "doch", "actually", "ne",
        "it", "that", "this", "back", "back on", "back off",
        "turn it", "turn that", "same setting", "last setting",
    }) then return nil end
    local setting = Registry:GetSetting(ctx.lastSetting)
    if not setting or setting.type ~= "boolean" then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Correct previous setting",
        summary = "Uses the last Assistant setting as context.",
    }
end

local function ParseSetting(text, ctx)
    local frameType = DetectFrameType(text, ctx)
    local direction = DetectDirection(text, ctx)
    local movementIntent = direction and ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset", "position", "x", "y" }) and not ContainsAny(text, { "anchor" })
    local attr = movementIntent and ((direction == "left" or direction == "right") and "offsetX" or "offsetY") or DetectAttribute(text, frameType)
    if not attr then return nil end

    local units = {}
    if frameType == "group" then
        units = DetectGroups(text)
    else
        units = DetectUnits(text)
    end
    if #units == 0 and (HasPhrase(text, "it") or HasPhrase(text, "that") or HasPhrase(text, "das") or HasPhrase(text, "more") or HasPhrase(text, "mehr")) then
        units = ContextUnits(ctx)
    end

    local value
    local relativeDelta
    if attr == "offsetX" or attr == "offsetY" then
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        value = nil
        relativeDelta = amount
    elseif attr == "width" or attr == "height" then
        relativeDelta = RelativeNumberDeltaForText(nil, text, 10)
        if relativeDelta == nil then value = FirstNumber(text) end
    else
        value = DetectBoolean(text)
    end

    if value == nil and relativeDelta == nil and attr ~= "enabled" then return nil end
    if value == nil and relativeDelta == nil and attr == "enabled" then value = DetectBoolean(text) end
    if value == nil and relativeDelta == nil then return nil end

    local candidates
    if #units > 0 then
        candidates = Registry:FindSettings({ units = units, frameType = frameType, attribute = attr })
    else
        candidates = Registry:FindSettings({ frameType = frameType, attribute = attr })
    end
    if #candidates == 0 then
        return {
            kind = "unknown",
            text = "That setting exists conceptually, but it is not registered for Assistant control yet.",
            status = "failed",
        }
    end
    if #units == 0 and #candidates > 1 then
        return {
            kind = "ambiguous",
            choices = BuildChanges(candidates, value, relativeDelta, direction),
            label = "Multiple matching settings",
        }
    end
    return {
        kind = "changes",
        changes = BuildChanges(candidates, value, relativeDelta, direction),
        label = "Assistant setting change",
        summary = "Registry-backed settings change.",
    }
end

function A.Parse(text)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = A.GetContext and A.GetContext() or {}
    if normalized == "" then return { kind = "empty" } end
    if ContainsAny(normalized, { "undo", "undo that", "undo last", "rueckgaengig" }) then
        return { kind = "undo" }
    end
    if ContainsAny(normalized, { "redo", "redo last" }) then
        return { kind = "redo" }
    end
    local parsed = ParseGuidedSetupFollowup(normalized, ctx)
        or BuildFollowup(normalized, ctx)
        or BuildBooleanCorrection(normalized, ctx)
        or ParseWorkflowLifecycle(normalized)
        or ParseProfileStagingState(normalized, raw)
        or ParseProfile(normalized, raw)
        or ParseAuraQuickPreset(normalized)
        or ParseAuraGroupCategoryBlacklist(normalized)
        or ParseAuraBlacklist(normalized, raw)
        or ParseClassPowerRootToggle(normalized)
        or ParseGameplayRootToggle(normalized)
        or ParsePresetWorkflow(normalized)
        or ParseScopedHelp(normalized)
        or ParseDashboardPanelAction(normalized)
        or ParseNavRailAction(normalized)
        or ParseSupportWorkflow(normalized)
        or ParseDiagnostic(normalized)
        or ParseMenuWindowAction(normalized)
        or ParseUnsupportedDetailShortcut(normalized)
        or ParseScopedOnlyOverride(normalized, raw)
        or ParseGroupFrameColorMode(normalized)
        or ParseMenuSelectorState(normalized)
        or ParsePortraitDetailShortcut(normalized)
        or ParseUnitDetailMove(normalized)
        or ParseBorderThicknessShortcut(normalized)
        or ParseUnitDetailOffsetShortcut(normalized)
        or ParseCastbarTextMoveShortcut(normalized)
        or ParseUnitOpacityShortcut(normalized)
        or ParseClassPowerAction(normalized)
        or ParseGameplayAction(normalized, raw)
        or ParseDarkModeBrightnessShortcut(normalized)
        or ParseGlobalBarsAction(normalized)
        or ParseCastbarGlobalDetail(normalized)
        or ParseCastbarPreviewAction(normalized)
        or ParseScopedOverrideReset(normalized)
        or ParseGuidedSetup(normalized)
        or ParseGroupCopyScopeState(normalized)
        or ParseGroupCopy(normalized)
        or ParseCopy(normalized)
        or BuildContextReset(normalized, ctx)
        or ParseColorAction(normalized)
        or ParseGroupSpellIndicatorAction(normalized, raw)
        or ParseGroupCornerIndicatorReset(normalized)
        or ParseGroupStatusPreview(normalized)
        or ParseUnitStatusPreview(normalized, ctx)
        or ParseUnitStatusIndicatorReset(normalized)
        or ParseGroupStatusIconReset(normalized)
        or ParseUnitStatusIndicatorMove(normalized)
        or ParseCustomAnchorSet(normalized, raw)
        or ParseCustomAnchorWorkflow(normalized)
        or ParseCustomAnchorClear(normalized)
        or ParseReset(normalized)
        or ParseOpen(normalized, raw)
        or ParseFontColorAction(normalized, raw)
        or ParseRegistryAlias(normalized, raw)
        or ParseSetting(normalized, ctx)
    if parsed then
        parsed.raw = raw
        parsed.normalized = normalized
        return parsed
    end
    return {
        kind = "unknown",
        raw = raw,
        normalized = normalized,
        text = "I do not know that setting yet.",
        status = "failed",
    }
end
