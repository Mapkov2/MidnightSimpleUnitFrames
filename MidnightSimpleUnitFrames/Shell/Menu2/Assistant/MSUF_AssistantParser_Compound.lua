local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P

local Trim = P.Trim
local Normalize = P.Normalize
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups

local COMMAND_STARTERS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift",
    "increase", "decrease", "raise", "lower", "select", "use", "apply",
    "setze", "stelle", "mach", "mache", "aktivieren", "deaktivieren", "einschalten", "ausschalten",
    "anzeigen", "verstecken", "einblenden", "ausblenden", "verschiebe", "verschieben", "waehle", "nutze",
}

local SKIP_TERMS = {
    "copy", "copy profile", "profile copy", "copy from profile", "rename profile", "profile import", "profile export",
    "import profile", "export profile", "guided setup", "setup guide", "blacklist", "whitelist",
    "kopiere", "kopieren", "profil kopieren", "profil umbenennen",
}

local VALUE_CONNECTORS = { " to ", " as ", " is ", " be ", " value ", " = ", " auf ", " zu ", " als ", " wert " }
local RELATIVE_VALUE_CONNECTORS = { " by ", " um " }
local SCOPE_RELATIONS = { " for ", " on ", " of ", " fuer ", " fur ", " vom ", " von " }

local function HasStarter(text)
    text = Normalize(text)
    for i = 1, #COMMAND_STARTERS do
        local starter = COMMAND_STARTERS[i]
        if text == starter or text:sub(1, #starter + 1) == starter .. " " then return true end
    end
    return false
end

local function ShouldSkip(text)
    if not ContainsAny(text, SKIP_TERMS) then return false end
    return not ContainsAny(text, { "width", "height", "alpha", "opacity", "name", "portrait", "color", "colour", "background" })
end

local function SafeText(raw)
    raw = tostring(raw or "")
    local out = {}
    local i = 1
    while i <= #raw do
        local ch = raw:sub(i, i)
        if ch == "," or ch == ";" then
            local prev = raw:sub(i - 1, i - 1)
            local j = i + 1
            while j <= #raw and raw:sub(j, j):match("%s") do j = j + 1 end
            local nextCh = raw:sub(j, j)
            if prev:match("%d") and nextCh:match("%d") then
                out[#out + 1] = ch
            else
                out[#out + 1] = " and "
            end
        else
            out[#out + 1] = ch
        end
        i = i + 1
    end
    return Normalize(table.concat(out))
end

local function SplitParts(text)
    text = Normalize(text)
    if text == "" then return nil end
    text = text:gsub("%s+plus%s+", " and "):gsub("%s+as well as%s+", " and "):gsub("%s+sowie%s+", " und ")
    local parts, current = {}, {}
    for word in text:gmatch("%S+") do
        if word == "and" or word == "und" then
            local part = Trim(table.concat(current, " "))
            if part ~= "" then parts[#parts + 1] = part end
            current = {}
        else
            current[#current + 1] = word
        end
    end
    local part = Trim(table.concat(current, " "))
    if part ~= "" then parts[#parts + 1] = part end
    if #parts > 6 then return nil end
    return #parts > 1 and parts or nil
end

local function LastConnector(text, connectors)
    local bestS
    for i = 1, #(connectors or {}) do
        local connector = connectors[i]
        local startAt = 1
        while true do
            local s, e = text:find(connector, startAt, true)
            if not s then break end
            if not bestS or s > bestS then bestS = s end
            startAt = e + 1
        end
    end
    return bestS
end

local function ContainsValueConnector(text)
    for i = 1, #VALUE_CONNECTORS do
        if text:find(VALUE_CONNECTORS[i], 1, true) then return true end
    end
    return false
end

local function ChangeCount(plan)
    return type(plan) == "table" and plan.kind == "changes" and type(plan.changes) == "table" and #plan.changes or 0
end

local ChangeId

local function PlanSignature(plan)
    local ids = {}
    for i = 1, #(plan and plan.changes or {}) do
        ids[#ids + 1] = ChangeId(plan.changes[i]) or ""
    end
    table.sort(ids)
    return table.concat(ids, "\030")
end

ChangeId = function(change)
    local setting = change and change.setting
    if not setting then return nil end
    local value = change.value
    if type(value) == "table" then
        value = tostring(value.r or value[1] or "") .. "," .. tostring(value.g or value[2] or "") .. "," .. tostring(value.b or value[3] or "")
    else
        value = tostring(value)
    end
    return tostring(setting.key or "") .. "\031" .. value .. "\031" .. tostring(change.relativeDelta) .. "\031" .. tostring(change.direction)
end

local function MergePlans(plans)
    local changes, seen = {}, {}
    for i = 1, #(plans or {}) do
        local plan = plans[i]
        if not (plan and plan.kind == "changes" and type(plan.changes) == "table" and #plan.changes > 0) then return nil end
        for j = 1, #plan.changes do
            local change = plan.changes[j]
            local id = ChangeId(change)
            if id and not seen[id] then
                seen[id] = true
                changes[#changes + 1] = change
            end
        end
    end
    if #changes < 2 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant setting change",
        summary = "Combined natural-language setting changes.",
        bulkSafe = true,
    }
end

local function SimpleParse(text)
    text = Trim(text)
    if text == "" then return nil end
    P._compoundDepth = (tonumber(P._compoundDepth) or 0) + 1
    local ok, parsed = pcall(A.Parse, text)
    P._compoundDepth = math.max(0, (tonumber(P._compoundDepth) or 1) - 1)
    if ok then return parsed end
    return nil
end

local function ScopePhrase(changes)
    local scopes, seen = {}, {}
    local function add(scope)
        scope = tostring(scope or "")
        if scope == "gf_party" then scope = "party" end
        if scope == "gf_raid" then scope = "raid" end
        if scope == "gf_mythicraid" or scope == "mythicraid" then scope = "mythic raid" end
        if scope == "" or scope == "global" or scope == "shared" or seen[scope] then return end
        seen[scope] = true
        scopes[#scopes + 1] = scope
    end
    for i = 1, #(changes or {}) do
        local setting = changes[i] and changes[i].setting
        local unit = tostring(setting and setting.unit or "")
        local keyScope = tostring(setting and setting.key or ""):match("^([^%.]+)")
        if unit ~= "" and unit ~= "global" and unit ~= "shared" then add(unit) else add(keyScope) end
    end
    return table.concat(scopes, " ")
end

local function Verb(plan)
    local boolValue, allBoolean, deltaSign = nil, true, nil
    for i = 1, #(plan and plan.changes or {}) do
        local change = plan.changes[i]
        local setting = change and change.setting
        if setting and setting.type == "boolean" and change.value ~= nil then
            if boolValue == nil then boolValue = change.value end
            if boolValue ~= change.value then allBoolean = false end
        else
            allBoolean = false
        end
        if type(change and change.relativeDelta) == "number" and change.relativeDelta ~= 0 then
            local sign = change.relativeDelta > 0 and 1 or -1
            if deltaSign == nil then deltaSign = sign elseif deltaSign ~= sign then deltaSign = 0 end
        end
    end
    if allBoolean and boolValue ~= nil then return boolValue and "turn on" or "turn off" end
    if deltaSign == 1 then return "increase" end
    if deltaSign == -1 then return "decrease" end
    return "set"
end

local function DetailSubject(plan)
    local subjects = {
        { term = "hptext", phrase = "hp text" },
        { term = "powertext", phrase = "power text" },
        { term = "portrait", phrase = "portrait" },
        { term = "castbar", phrase = "castbar" },
        { term = "power", phrase = "power" },
        { term = "name", phrase = "name" },
        { term = "health", phrase = "health" },
        { term = "deadbg", phrase = "dead background" },
    }
    local best
    for s = 1, #subjects do
        local spec = subjects[s]
        local all = true
        for i = 1, #(plan and plan.changes or {}) do
            local setting = plan.changes[i] and plan.changes[i].setting
            local hay = tostring(setting and setting.key or "") .. " " .. tostring(setting and setting.attribute or "") .. " " .. tostring(setting and setting.category or "")
            hay = hay:lower():gsub("%s+", "")
            if not hay:find(spec.term, 1, true) then
                all = false
                break
            end
        end
        if all then
            best = spec.phrase
            break
        end
    end
    return best or ""
end

local function Prefix(plan)
    local verb = Verb(plan)
    local scope = ScopePhrase(plan and plan.changes)
    local detail = DetailSubject(plan)
    if detail ~= "" and verb == "set" then scope = Trim(scope .. " " .. detail) end
    if scope ~= "" then return Trim(verb .. " " .. scope), verb end
    return verb, verb
end

local function HasScope(text)
    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    return (#units + #groups) > 0 or ContainsAny(text, { "all", "every", "alle", "jede", "jeder", "jedes" })
end

local function SegmentCommand(segment, prefix, verb)
    segment = Trim(segment)
    if segment == "" then return nil end
    segment = segment:gsub("%f[%w]names%f[%W]", "name"):gsub("%f[%w]portraits%f[%W]", "portrait")
    if HasStarter(segment) then return segment end
    if HasScope(segment) then return Trim(tostring(verb or "set") .. " " .. segment) end
    return Trim(tostring(prefix or "set") .. " " .. segment)
end

local function BooleanLead(text)
    text = Normalize(text)
    if text:sub(1, 9) == "turn off " then return "turn off", Trim(text:sub(10)) end
    if text:sub(1, 8) == "turn on " then return "turn on", Trim(text:sub(9)) end
    if text:sub(1, 8) == "disable " then return "turn off", Trim(text:sub(9)) end
    if text:sub(1, 7) == "enable " then return "turn on", Trim(text:sub(8)) end
    if text:sub(1, 5) == "hide " then return "turn off", Trim(text:sub(6)) end
    if text:sub(1, 5) == "show " then return "turn on", Trim(text:sub(6)) end
    return nil, text
end

local function SingularItem(text)
    return Trim((text or "")
        :gsub("%f[%w]names%f[%W]", "name")
        :gsub("%f[%w]portraits%f[%W]", "portrait")
        :gsub("%f[%w]castbar icons%f[%W]", "castbar icon")
        :gsub("%f[%w]status icons%f[%W]", "status icon")
        :gsub("%f[%w]icons%f[%W]", "icon"))
end

local function ScopeLabels(tail)
    local out, seen = {}, {}
    local function add(label)
        label = tostring(label or "")
        if label == "" or seen[label] then return end
        seen[label] = true
        out[#out + 1] = label
    end
    local explicitUnits = {
        { label = "player", terms = { "player", "spieler", "self", "ich" } },
        { label = "target", terms = { "target", "ziel" } },
        { label = "focus", terms = { "focus", "fokus" } },
        { label = "pet", terms = { "pet", "begleiter" } },
        { label = "boss", terms = { "boss" } },
        { label = "targettarget", terms = { "targettarget", "target of target", "tot", "ziel des ziels" } },
        { label = "focustarget", terms = { "focustarget", "focus target", "fokus ziel" } },
    }
    for i = 1, #explicitUnits do
        if ContainsAny(tail, explicitUnits[i].terms) then add(explicitUnits[i].label) end
    end
    if ContainsAny(tail, { "party" }) then add("party") end
    local hasMythicRaid = ContainsAny(tail, { "mythic raid", "mythicraid" })
    if hasMythicRaid then add("mythic raid") end
    if not hasMythicRaid and ContainsAny(tail, { "raid" }) then add("raid") end
    local units = DetectUnits(tail)
    for i = 1, #units do add(units[i]) end
    local groups = DetectGroups(tail)
    for i = 1, #groups do
        local group = groups[i] == "mythicraid" and "mythic raid" or groups[i]
        add(group)
    end
    return out
end

local SCOPE_REMOVE_TERMS = {
    "targettarget", "target of target", "tot", "focustarget", "focus target",
    "mythic raid", "mythicraid", "player", "target", "focus", "pet", "boss", "party", "raid",
    "frame", "frames", "unitframe", "unitframes", "group frame", "group frames",
    "and", "und",
}

local function RemoveScopeTerms(text)
    local out = " " .. Normalize(text) .. " "
    for i = 1, #SCOPE_REMOVE_TERMS do
        local term = Normalize(SCOPE_REMOVE_TERMS[i])
        if term ~= "" then
            out = out:gsub(" " .. term:gsub("([^%w%s])", "%%%1") .. " ", " ")
        end
    end
    return SingularItem(Normalize(out))
end

local function AddScopeLabels(out, seen, text)
    local labels = ScopeLabels(text)
    for i = 1, #labels do
        local label = labels[i]
        if label ~= "" and not seen[label] then
            seen[label] = true
            out[#out + 1] = label
        end
    end
end

local function BuildDistributedCommands(lead, scopes, item)
    item = SingularItem(item)
    if item == "" or #(scopes or {}) < 2 then return nil end
    local commands = {}
    for i = 1, #scopes do
        commands[#commands + 1] = Trim(lead .. " " .. scopes[i] .. " " .. item)
    end
    return commands
end

local function TrailingScopeItemCommands(parts)
    if not parts or #parts < 2 then return nil end
    local lead, firstRest = BooleanLead(parts[1])
    if not lead then return nil end
    local scopes, seen = {}, {}
    local firstItem = RemoveScopeTerms(firstRest)
    if firstItem ~= "" then return nil end
    AddScopeLabels(scopes, seen, firstRest)
    for i = 2, #parts - 1 do
        if RemoveScopeTerms(parts[i]) ~= "" then return nil end
        AddScopeLabels(scopes, seen, parts[i])
    end
    local item = RemoveScopeTerms(parts[#parts])
    AddScopeLabels(scopes, seen, parts[#parts])
    return BuildDistributedCommands(lead, scopes, item)
end

local function NoJoinScopeItemCommands(text)
    local lead, rest = BooleanLead(text)
    if not lead then return nil end
    local item, tail = rest:match("^(.-)%s+for%s+(.+)$")
    if not item then item, tail = rest:match("^(.-)%s+on%s+(.+)$") end
    if item and tail then
        local scopes, seen = {}, {}
        AddScopeLabels(scopes, seen, tail)
        return BuildDistributedCommands(lead, scopes, item)
    end
    local scopes, seen = {}, {}
    AddScopeLabels(scopes, seen, rest)
    item = RemoveScopeTerms(rest)
    if item ~= "name" and item ~= "portrait" then return nil end
    return BuildDistributedCommands(lead, scopes, item)
end

local function DistributedScopeCommands(parts, tail)
    local lead, firstItem = BooleanLead(parts and parts[1])
    if not lead then return nil end
    local scopes = ScopeLabels(tail)
    if #scopes == 0 then return nil end
    local commands = {}
    for p = 1, #parts do
        local item = p == 1 and firstItem or parts[p]
        item = Trim((item or ""):gsub("%f[%w]names%f[%W]", "name"):gsub("%f[%w]portraits%f[%W]", "portrait"))
        if item == "" then return nil end
        for s = 1, #scopes do
            commands[#commands + 1] = Trim(lead .. " " .. scopes[s] .. " " .. item)
        end
    end
    return commands
end

local ParseCommands

local function StripCommandLead(text)
    text = Normalize(text)
    for _, lead in ipairs({ "set", "change", "make", "turn", "show", "hide", "enable", "disable", "increase", "decrease", "raise", "lower", "setze", "stelle", "mach", "mache" }) do
        if text == lead then return "" end
        if text:sub(1, #lead + 1) == lead .. " " then return Trim(text:sub(#lead + 2)) end
    end
    return text
end

local function ParseWidthHeight(scopeText, widthValue, heightValue)
    scopeText = StripCommandLead(scopeText)
    if scopeText == "" then return nil end
    return ParseCommands({
        "set " .. scopeText .. " width to " .. tostring(widthValue),
        "set " .. scopeText .. " height to " .. tostring(heightValue),
    })
end

local function CleanSizeScope(scopeText)
    scopeText = StripCommandLead(scopeText)
    scopeText = Normalize(scopeText):gsub("^and%s+", ""):gsub("^und%s+", "")
    scopeText = scopeText:gsub("%s+size$", ""):gsub("%s+frame$", ""):gsub("%s+frames$", "")
    return Trim(scopeText)
end

local function MultiSizePairs(text)
    local matches = {}
    local patterns = {
        "([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)",
        "([-+]?%d+%.?%d*)%s+by%s+([-+]?%d+%.?%d*)",
    }
    for p = 1, #patterns do
        local found = {}
        local startAt = 1
        while true do
            local s, e, w, h = text:find(patterns[p], startAt)
            if not s then break end
            found[#found + 1] = { s = s, e = e, w = w, h = h }
            startAt = e + 1
        end
        if #found >= 2 then
            matches = found
            break
        end
    end
    if #matches < 2 or #matches > 6 then return nil end

    local commands = {}
    local prevEnd = 1
    for i = 1, #matches do
        local m = matches[i]
        local scope = CleanSizeScope(text:sub(prevEnd, m.s - 1))
        if scope == "" then return nil end
        commands[#commands + 1] = "set " .. scope .. " width to " .. tostring(m.w)
        commands[#commands + 1] = "set " .. scope .. " height to " .. tostring(m.h)
        prevEnd = m.e + 1
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function SizePair(text)
    local scope, widthValue, heightValue = text:match("^(.-)%s+size%s+to%s+([-+]?%d+%.?%d*)%s+by%s+([-+]?%d+%.?%d*)$")
    if not scope then scope, widthValue, heightValue = text:match("^(.-)%s+size%s+([-+]?%d+%.?%d*)%s+by%s+([-+]?%d+%.?%d*)$") end
    if not scope then scope, widthValue, heightValue = text:match("^(.-)%s+size%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not scope then scope, widthValue, heightValue = text:match("^(.-)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not scope then scope, widthValue, heightValue = text:match("^(.-)%s+([-+]?%d+%.?%d*)%s+wide%s+and%s+([-+]?%d+%.?%d*)%s+%a+$") end
    if not scope then scope, widthValue, heightValue = text:match("^(.-)%s+([-+]?%d+%.?%d*)%s+wide%s+([-+]?%d+%.?%d*)%s+%a+$") end
    if not (scope and widthValue and heightValue) then return nil end
    return ParseWidthHeight(scope, widthValue, heightValue)
end

local ATTR_SPECS = {
    { phrase = "portrait border thickness", terms = { "portrait border thickness", "portrait border size" } },
    { phrase = "power bar height", terms = { "power bar height", "mana bar height", "energy bar height" } },
    { phrase = "background opacity", terms = { "background opacity", "bg opacity", "track opacity", "hp track opacity" } },
    { phrase = "border thickness", terms = { "border thickness", "outline thickness", "border size", "outline size" } },
    { phrase = "icon size", terms = { "icon size", "spell icon size" } },
    { phrase = "text size", terms = { "text size", "font size" } },
    { phrase = "portrait size", terms = { "portrait size" } },
    { phrase = "height", terms = { "height", "heights", "tall", "high", "hoehe" } },
    { phrase = "width", terms = { "width", "widths", "wide", "breite" } },
    { phrase = "x offset", terms = { "x offset", "x offsets", "offset x", "x" } },
    { phrase = "y offset", terms = { "y offset", "y offsets", "offset y", "y" } },
    { phrase = "alpha", terms = { "alpha", "opacity" } },
}

local ATTR_TERMS_BY_LENGTH

local function AttrTermsByLength()
    if ATTR_TERMS_BY_LENGTH then return ATTR_TERMS_BY_LENGTH end
    local out = {}
    for i = 1, #ATTR_SPECS do
        local spec = ATTR_SPECS[i]
        for j = 1, #spec.terms do
            out[#out + 1] = { term = Normalize(spec.terms[j]), phrase = spec.phrase }
        end
    end
    table.sort(out, function(a, b) return #a.term > #b.term end)
    ATTR_TERMS_BY_LENGTH = out
    return ATTR_TERMS_BY_LENGTH
end

local function StripValueTail(text)
    text = Normalize((text or ""):gsub("=", " "))
    text = text:gsub("%s+to$", ""):gsub("%s+as$", ""):gsub("%s+is$", ""):gsub("%s+be$", "")
    text = text:gsub("%s+auf$", ""):gsub("%s+zu$", ""):gsub("%s+als$", ""):gsub("%s+wert$", "")
    return Trim(text)
end

local function ExtractAttr(segment)
    segment = StripValueTail(segment)
    if segment == "" then return nil end
    for i = 1, #ATTR_SPECS do
        local spec = ATTR_SPECS[i]
        for j = 1, #spec.terms do
            local term = Normalize(spec.terms[j])
            if segment == term then return "", spec.phrase end
            if #segment > #term and segment:sub(-#term) == term and segment:sub(#segment - #term, #segment - #term) == " " then
                return Trim(segment:sub(1, #segment - #term)), spec.phrase
            end
        end
    end
    return nil
end

local AddScopedAttributeCommands

local function MatchAttrAtStart(text)
    text = Normalize(text)
    local terms = AttrTermsByLength()
    for i = 1, #terms do
        local term = terms[i].term
        if text == term then return terms[i].phrase, #term end
        if #text > #term and text:sub(1, #term) == term and text:sub(#term + 1, #term + 1) == " " then
            return terms[i].phrase, #term
        end
    end
    return nil
end

local function ParseAttributeList(rest)
    rest = Normalize(rest)
    local attrs = {}
    local needConnector = false
    while rest ~= "" do
        if needConnector then
            if rest:sub(1, 4) == "and " then
                rest = Trim(rest:sub(5))
            elseif rest:sub(1, 4) == "und " then
                rest = Trim(rest:sub(5))
            elseif not MatchAttrAtStart(rest) then
                return nil
            else
                rest = Trim(rest)
            end
        end
        local attr, used = MatchAttrAtStart(rest)
        if not attr then return nil end
        attrs[#attrs + 1] = attr
        rest = Trim(rest:sub(used + 1))
        needConnector = true
    end
    return #attrs > 0 and attrs or nil
end

local function NumberList(text)
    text = Normalize(text or "")
    local values = {}
    for value in text:gmatch("[-+]?%d+%.?%d*") do values[#values + 1] = value end
    if #values == 0 then return nil end
    local leftover = text:gsub("[-+]?%d+%.?%d*", " ")
    leftover = leftover:gsub("%f[%w]and%f[%W]", " "):gsub("%f[%w]und%f[%W]", " ")
    leftover = leftover:gsub("%f[%w]to%f[%W]", " "):gsub("%f[%w]as%f[%W]", " ")
    leftover = leftover:gsub("%f[%w]is%f[%W]", " "):gsub("%f[%w]be%f[%W]", " ")
    leftover = leftover:gsub("%f[%w]value%f[%W]", " "):gsub("%f[%w]auf%f[%W]", " ")
    leftover = leftover:gsub("%f[%w]zu%f[%W]", " "):gsub("%f[%w]als%f[%W]", " ")
    leftover = leftover:gsub("%f[%w]wert%f[%W]", " "):gsub("%f[%w]by%f[%W]", " ")
    leftover = leftover:gsub("%f[%w]um%f[%W]", " "):gsub("=", " ")
    leftover = Trim(leftover:gsub("%s+", " "))
    return leftover == "" and values or nil
end

local function AttributeListPrefix(text)
    text = Normalize(text)
    for pos = 1, #text do
        if pos == 1 or text:sub(pos - 1, pos - 1) == " " then
            local attrs = ParseAttributeList(text:sub(pos))
            if attrs and #attrs >= 2 then
                local prefix = Trim(text:sub(1, pos - 1))
                prefix = prefix:gsub("%s+and$", ""):gsub("%s+und$", "")
                return Trim(prefix), attrs
            end
        end
    end
    return nil
end

local function AttributeListValues(text)
    local s = LastConnector(text, VALUE_CONNECTORS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    if body:find("[-+]?%d+%.?%d*") then return nil end
    local values = NumberList(text:sub(s))
    if not values or #values < 2 or #values > 6 then return nil end
    local prefix, attrs = AttributeListPrefix(body)
    if not prefix or prefix == "" or not attrs or #attrs ~= #values then return nil end

    local commands = {}
    for i = 1, #attrs do
        if not AddScopedAttributeCommands(commands, StripCommandLead(prefix), attrs[i], values[i]) then return nil end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function AttributeListTrailingNumbers(text)
    local pairText = Normalize((text or ""):gsub("=", " "))
    local s = pairText:find("[-+]?%d+%.?%d*")
    if not s then return nil end
    local body = Trim(pairText:sub(1, s - 1))
    local values = NumberList(pairText:sub(s))
    if not values or #values < 2 or #values > 6 then return nil end
    local prefix, attrs = AttributeListPrefix(body)
    if not prefix or prefix == "" or not attrs or #attrs ~= #values then return nil end

    local commands = {}
    for i = 1, #attrs do
        if not AddScopedAttributeCommands(commands, StripCommandLead(prefix), attrs[i], values[i]) then return nil end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function DetailScopeForAttr(scope, attr)
    scope = Trim(scope or "")
    attr = Normalize(attr or "")
    if scope == "" then return "" end
    if attr:sub(1, 8) == "portrait" and not ContainsAny(scope, { "portrait" }) then
        return Trim(scope .. " portrait")
    end
    if (attr:sub(1, 7) == "hp text" or attr:sub(1, 11) == "health text") and not ContainsAny(scope, { "hp text", "health text" }) then
        return Trim(scope .. " hp text")
    end
    if attr:sub(1, 10) == "power text" and not ContainsAny(scope, { "power text" }) then
        return Trim(scope .. " power text")
    end
    return scope
end

local function LooksLikeOnlyScopes(text)
    return text ~= "" and HasScope(text) and RemoveScopeTerms(text) == ""
end

local function DistributableScopePrefixes(scope)
    scope = Trim(scope or "")
    local scopes = ScopeLabels(scope)
    if #scopes <= 1 then return nil end
    local detail = RemoveScopeTerms(scope)
    if detail ~= "" and not ContainsAny(detail, {
        "castbar", "cast bar", "portrait", "power bar", "mana bar", "hp text", "health text", "power text", "name text",
    }) then
        return nil
    end
    local out = {}
    for i = 1, #scopes do
        out[#out + 1] = Trim(scopes[i] .. " " .. detail)
    end
    return out
end

AddScopedAttributeCommands = function(commands, scope, attr, value)
    scope = Trim(scope or "")
    if scope == "" then return false end
    local scopes = DistributableScopePrefixes(scope) or (LooksLikeOnlyScopes(scope) and ScopeLabels(scope) or nil)
    if scopes and #scopes > 1 then
        for i = 1, #scopes do
            commands[#commands + 1] = Trim("set " .. scopes[i] .. " " .. attr .. " to " .. tostring(value))
        end
    else
        commands[#commands + 1] = Trim("set " .. scope .. " " .. attr .. " to " .. tostring(value))
    end
    return true
end

local function BooleanVerbForText(text)
    text = Normalize(text)
    if ContainsAny(text, { "off", "disable", "disabled", "false", "no", "hide", "hidden", "aus", "deaktivieren", "ausschalten" }) then return "turn off" end
    if ContainsAny(text, { "on", "enable", "enabled", "true", "yes", "show", "visible", "keep", "an", "aktivieren", "einschalten" }) then return "turn on" end
    return nil
end

local function StripBooleanWords(text)
    local out = " " .. Normalize(text) .. " "
    for _, word in ipairs({ "on", "off", "enable", "enabled", "disable", "disabled", "true", "false", "yes", "no", "show", "hide", "visible", "hidden", "keep", "and", "und" }) do
        out = out:gsub(" " .. word .. " ", " ")
    end
    return SingularItem(Normalize(out))
end

local function AttributeNumberPairs(text)
    local pairText = Normalize((text or ""):gsub("=", " "))
    local segments, values = {}, {}
    local pos = 1
    while true do
        local s, e = pairText:find("[-+]?%d+%.?%d*", pos)
        if not s then break end
        segments[#segments + 1] = Trim(pairText:sub(pos, s - 1))
        values[#values + 1] = pairText:sub(s, e)
        pos = e + 1
    end
    local tail = Trim(pairText:sub(pos))
    if #values < 1 or #values > 6 then return nil end

    local firstPrefix
    local detailScope
    local currentScope
    local commands = {}
    for i = 1, #values do
        local rawSegment = segments[i]
        local prefix, attr = ExtractAttr(rawSegment)
        if not attr then return nil end
        local rawPrefix = prefix
        local prePlan
        if i == 1 and prefix and prefix ~= "" then
            prePlan = SimpleParse(prefix)
            if not (prePlan and prePlan.kind == "changes" and type(prePlan.changes) == "table" and #prePlan.changes > 0) then prePlan = nil end
        end
        local usedPrePlan = prePlan ~= nil
        prefix = StripCommandLead(prefix or "")
        if i == 1 then
            if prePlan then
                commands[#commands + 1] = rawPrefix
                firstPrefix = ScopePhrase(prePlan.changes)
                local detail = DetailSubject(prePlan)
                if detail ~= "" then firstPrefix = Trim(firstPrefix .. " " .. detail) end
                prefix = ""
            else
                firstPrefix = prefix
            end
            if firstPrefix == "" then return nil end
            detailScope = DetailScopeForAttr(firstPrefix, attr)
            currentScope = detailScope ~= "" and detailScope or firstPrefix
        end
        local scope = currentScope or firstPrefix
        if not usedPrePlan and prefix ~= "" and HasScope(prefix) then
            scope = prefix
            currentScope = DetailScopeForAttr(prefix, attr)
        elseif prefix == "" and currentScope ~= "" and not attr:find("portrait", 1, true) and not attr:find("hp text", 1, true) and not attr:find("power text", 1, true) then
            scope = currentScope
        end
        if not AddScopedAttributeCommands(commands, scope, attr, values[i]) then return nil end
    end
    if tail ~= "" then
        local verb = BooleanVerbForText(tail)
        local item = verb and StripBooleanWords(tail) or ""
        if verb and item ~= "" then
            local scope = detailScope ~= "" and detailScope or firstPrefix
            commands[#commands + 1] = Trim(verb .. " " .. scope .. " " .. item)
        end
    end
    return ParseCommands(commands)
end

local function ScopedValueTailPairs(text)
    local pairText = Normalize((text or ""):gsub("=", " "))
    local segments, values = {}, {}
    local pos = 1
    while true do
        local s, e = pairText:find("[-+]?%d+%.?%d*", pos)
        if not s then break end
        segments[#segments + 1] = Trim(pairText:sub(pos, s - 1))
        values[#values + 1] = pairText:sub(s, e)
        pos = e + 1
    end
    if #values < 2 or #values > 6 then return nil end

    local firstPrefix, attr = ExtractAttr(segments[1])
    if not (firstPrefix and attr) then return nil end
    firstPrefix = StripCommandLead(firstPrefix)
    if firstPrefix == "" then return nil end

    local commands = {}
    if not AddScopedAttributeCommands(commands, firstPrefix, attr, values[1]) then return nil end
    for i = 2, #values do
        local scope = StripCommandLead(StripValueTail(segments[i]))
        scope = scope:gsub("^and%s+", ""):gsub("^und%s+", "")
        scope = Trim(scope)
        if not LooksLikeOnlyScopes(scope) then return nil end
        if not AddScopedAttributeCommands(commands, scope, attr, values[i]) then return nil end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function StripRelativeTail(text)
    text = Normalize(text or "")
    text = text:gsub("%s+by$", ""):gsub("%s+um$", "")
    return Trim(text)
end

local function RelativeLead(text)
    text = Normalize(text or "")
    for _, lead in ipairs({ "increase", "raise", "decrease", "lower" }) do
        if text == lead or text:sub(1, #lead + 1) == lead .. " " then return lead end
    end
    if ContainsAny(text, { "bigger", "larger", "wider", "taller", "higher", "more", "grow", "increase", "raise" }) then return "increase" end
    if ContainsAny(text, { "smaller", "shorter", "narrower", "lower", "less", "decrease", "reduce" }) then return "decrease" end
    return nil
end

local function StripRelativeDescriptor(text)
    text = Normalize(text or "")
    for _, word in ipairs({ "bigger", "larger", "wider", "taller", "higher", "smaller", "shorter", "narrower", "lower", "more", "less" }) do
        text = text:gsub("%s+" .. word .. "$", "")
    end
    return Trim(text)
end

local function AddScopedRelativeAttributeCommands(commands, lead, scope, attr, value)
    scope = Trim(scope or "")
    lead = (lead == "decrease" or lead == "lower") and "decrease" or "increase"
    local scopes = DistributableScopePrefixes(scope) or (LooksLikeOnlyScopes(scope) and ScopeLabels(scope) or nil)
    if scopes and #scopes > 1 then
        for i = 1, #scopes do
            commands[#commands + 1] = Trim(lead .. " " .. scopes[i] .. " " .. attr .. " by " .. tostring(value))
        end
    elseif scope ~= "" then
        commands[#commands + 1] = Trim(lead .. " " .. scope .. " " .. attr .. " by " .. tostring(value))
    else
        return false
    end
    return true
end

local function AttributeListRelativeValues(text)
    local s = LastConnector(text, RELATIVE_VALUE_CONNECTORS)
    if not s then return nil end
    local rawBody = Trim(text:sub(1, s - 1))
    local body = StripRelativeDescriptor(rawBody)
    local values = NumberList(text:sub(s))
    if not values or #values < 2 or #values > 6 then return nil end
    local lead = RelativeLead(rawBody)
    if not lead then return nil end
    local prefix, attrs = AttributeListPrefix(body)
    if not prefix or prefix == "" or not attrs or #attrs ~= #values then return nil end

    local commands = {}
    for i = 1, #attrs do
        if not AddScopedRelativeAttributeCommands(commands, lead, StripCommandLead(prefix), attrs[i], values[i]) then return nil end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function SharedAttributeValue(text)
    local s = LastConnector(text, VALUE_CONNECTORS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    if body:find("[-+]?%d+%.?%d*") then return nil end
    local values = NumberList(text:sub(s))
    if not values or #values ~= 1 then return nil end
    local prefix, attr = ExtractAttr(body)
    if not prefix or not attr then return nil end
    prefix = StripCommandLead(prefix)
    if prefix == "" or #ScopeLabels(prefix) < 2 then return nil end
    local commands = {}
    if not AddScopedAttributeCommands(commands, prefix, attr, values[1]) then return nil end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function SharedAttributeRelativeValue(text)
    local s = LastConnector(text, RELATIVE_VALUE_CONNECTORS)
    if not s then return nil end
    local rawBody = Trim(text:sub(1, s - 1))
    if rawBody:find("[-+]?%d+%.?%d*") then return nil end
    local values = NumberList(text:sub(s))
    if not values or #values ~= 1 then return nil end
    local lead = RelativeLead(rawBody)
    if not lead then return nil end
    local prefix, attr = ExtractAttr(StripRelativeDescriptor(rawBody))
    if not prefix or not attr then return nil end
    prefix = StripCommandLead(prefix)
    if prefix == "" or #ScopeLabels(prefix) < 2 then return nil end
    local commands = {}
    if not AddScopedRelativeAttributeCommands(commands, lead, prefix, attr, values[1]) then return nil end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function ScopedRelativeValueTailPairs(text)
    local pairText = Normalize(text or "")
    if not pairText:find(" by ", 1, true) and not pairText:find(" um ", 1, true) then return nil end
    local segments, values = {}, {}
    local pos = 1
    while true do
        local s, e = pairText:find("[-+]?%d+%.?%d*", pos)
        if not s then break end
        segments[#segments + 1] = Trim(pairText:sub(pos, s - 1))
        values[#values + 1] = pairText:sub(s, e)
        pos = e + 1
    end
    if #values < 2 or #values > 6 then return nil end

    local lead = RelativeLead(segments[1])
    if not lead then return nil end
    local firstPrefix, attr = ExtractAttr(StripRelativeTail(segments[1]))
    if not (firstPrefix and attr) then return nil end
    firstPrefix = StripCommandLead(firstPrefix)
    if firstPrefix == "" then return nil end

    local commands = { Trim(lead .. " " .. firstPrefix .. " " .. attr .. " by " .. tostring(values[1])) }
    for i = 2, #values do
        local scope = StripCommandLead(StripRelativeTail(segments[i]))
        scope = scope:gsub("^and%s+", ""):gsub("^und%s+", "")
        scope = Trim(scope)
        if not LooksLikeOnlyScopes(scope) then return nil end
        local scopes = ScopeLabels(scope)
        if #scopes == 0 then return nil end
        for s = 1, #scopes do
            commands[#commands + 1] = Trim(lead .. " " .. scopes[s] .. " " .. attr .. " by " .. tostring(values[i]))
        end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

ParseCommands = function(commands)
    if #(commands or {}) > 12 then return nil end
    local plans = {}
    for i = 1, #(commands or {}) do
        local parsed = SimpleParse(commands[i])
        if not (parsed and parsed.kind == "changes" and type(parsed.changes) == "table" and #parsed.changes > 0) then return nil end
        plans[#plans + 1] = parsed
    end
    return MergePlans(plans)
end

local function HybridSizeTail(text)
    local before, scope, widthValue, heightValue = text:match("^(.-)%s+(mythic raid)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$")
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(targettarget)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(focustarget)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(player)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(target)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(focus)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(party)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then before, scope, widthValue, heightValue = text:match("^(.-)%s+(raid)%s+([-+]?%d+%.?%d*)%s*x%s*([-+]?%d+%.?%d*)$") end
    if not before then return nil end

    local beforePlan = AttributeNumberPairs(before)
    local tailPlan = ParseWidthHeight(scope, widthValue, heightValue)
    if not beforePlan or not tailPlan then return nil end
    return MergePlans({ beforePlan, tailPlan })
end

local function SharedScopeValue(text)
    local s = LastConnector(text, VALUE_CONNECTORS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    local suffix = Trim(text:sub(s))
    if body == "" or suffix == "" or not body:find(" and ", 1, true) then return nil end
    local parts = SplitParts(body)
    if not parts or #parts < 2 then return nil end

    local lead = "set"
    local first = StripCommandLead(parts[1])
    if first == parts[1] then
        local maybeLead, rest = parts[1]:match("^(%S+)%s+(.+)$")
        if maybeLead and HasStarter(maybeLead) then
            lead, first = maybeLead, rest
        end
    end

    local scopes, seen = {}, {}
    AddScopeLabels(scopes, seen, first)
    for i = 2, #parts do AddScopeLabels(scopes, seen, parts[i]) end
    if #scopes < 2 then return nil end

    local item = RemoveScopeTerms(parts[#parts])
    if item == "" then return nil end
    local commands = {}
    for i = 1, #scopes do
        commands[#commands + 1] = Trim(lead .. " " .. scopes[i] .. " " .. item .. " " .. suffix)
    end
    return ParseCommands(commands)
end

local function SharedScopeRelativeValue(text)
    local s = LastConnector(text, RELATIVE_VALUE_CONNECTORS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    local suffix = Trim(text:sub(s))
    if body == "" or suffix == "" or not body:find(" and ", 1, true) then return nil end
    local parts = SplitParts(body)
    if not parts or #parts < 2 then return nil end

    local lead = "increase"
    local first = StripCommandLead(parts[1])
    if first == parts[1] then
        local maybeLead, rest = parts[1]:match("^(%S+)%s+(.+)$")
        if maybeLead and HasStarter(maybeLead) then
            lead, first = maybeLead, rest
        end
    else
        local maybeLead = Normalize(parts[1]):match("^(%S+)")
        if maybeLead and HasStarter(maybeLead) then lead = maybeLead end
    end

    local scopes, seen = {}, {}
    AddScopeLabels(scopes, seen, first)
    for i = 2, #parts do AddScopeLabels(scopes, seen, parts[i]) end
    if #scopes < 2 then return nil end

    local item = RemoveScopeTerms(parts[#parts])
    if item == "" then return nil end
    local commands = {}
    for i = 1, #scopes do
        commands[#commands + 1] = Trim(lead .. " " .. scopes[i] .. " " .. item .. " " .. suffix)
    end
    return ParseCommands(commands)
end

local function SharedValue(text)
    local s = LastConnector(text, VALUE_CONNECTORS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    local suffix = Trim(text:sub(s))
    if body == "" or suffix == "" or not body:find(" and ", 1, true) then return nil end
    if ContainsValueConnector(body) then return nil end
    local parts = SplitParts(body)
    if not parts then return nil end
    local firstCommand = Trim(parts[1] .. " " .. suffix)
    local firstPlan = SimpleParse(firstCommand)
    if not (firstPlan and firstPlan.kind == "changes") then return nil end
    local prefix, verb = Prefix(firstPlan)
    local commands = { firstCommand }
    for i = 2, #parts do
        local base = SegmentCommand(parts[i], prefix, verb)
        if not base then return nil end
        commands[#commands + 1] = Trim(base .. " " .. suffix)
    end
    return ParseCommands(commands)
end

local function ScopeTailConcrete(tail)
    if tail == "" then return false end
    local units = DetectUnits(tail)
    local groups = DetectGroups(tail)
    return (#units + #groups) > 0 or ContainsAny(tail, {
        "all unitframes", "all unit frames", "all group frames", "all groups",
        "every unitframe", "every group frame", "alle unitframes", "alle gruppenframes",
    })
end

local function SharedScope(text)
    local s = LastConnector(text, SCOPE_RELATIONS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    local tail = Trim(text:sub(s))
    if tail:sub(1, 3) == "on " and body:match("%f[%w]turn$") then return nil end
    if body == "" or tail == "" or not body:find(" and ", 1, true) then return nil end
    if not ScopeTailConcrete(tail) then return nil end
    local parts = SplitParts(body)
    if not parts then return nil end
    local distributed = DistributedScopeCommands(parts, tail)
    local distributedPlan = distributed and ParseCommands(distributed)
    if distributedPlan then return distributedPlan end
    local firstCommand = Trim(parts[1] .. " " .. tail)
    local firstPlan = SimpleParse(firstCommand)
    if not (firstPlan and firstPlan.kind == "changes") then return nil end
    local prefix, verb = Prefix(firstPlan)
    local commands = { firstCommand }
    for i = 2, #parts do
        local base = SegmentCommand(parts[i], prefix, verb)
        if not base then return nil end
        commands[#commands + 1] = Trim(base .. " " .. tail)
    end
    return ParseCommands(commands)
end

local function KeepButBoolean(text)
    local first, second = text:match("^(.-)%s+but%s+keep%s+(.+)$")
    if not first then first, second = text:match("^(.-)%s+but%s+leave%s+(.+)$") end
    if not first then first, second = text:match("^(.-)%s+but%s+turn%s+(.+)$") end
    if not (first and second) then return nil end
    local firstPlan = SimpleParse(first)
    if not (firstPlan and firstPlan.kind == "changes" and #firstPlan.changes > 0) then return nil end
    local verb = BooleanVerbForText(second)
    local item = verb and StripBooleanWords(second) or ""
    if item == "" then return nil end
    local scope = ScopePhrase(firstPlan.changes)
    if scope == "" then return nil end
    local secondPlan = SimpleParse(Trim(verb .. " " .. scope .. " " .. item))
    if not (secondPlan and secondPlan.kind == "changes" and #secondPlan.changes > 0) then return nil end
    return MergePlans({ firstPlan, secondPlan })
end

local BOOL_WORDS = {
    on = "turn on", enabled = "turn on", ["true"] = "turn on", yes = "turn on", show = "turn on",
    off = "turn off", disabled = "turn off", ["false"] = "turn off", no = "turn off", hide = "turn off",
}

local BOOLEAN_ITEM_TERMS = {
    { term = "castbar icons", item = "castbar icon" },
    { term = "cast bar icons", item = "castbar icon" },
    { term = "status icons", item = "status icon" },
    { term = "health bars", item = "health bar" },
    { term = "power bars", item = "power bar" },
    { term = "mana bars", item = "mana bar" },
    { term = "castbars", item = "castbar" },
    { term = "cast bars", item = "castbar" },
    { term = "portraits", item = "portrait" },
    { term = "names", item = "name" },
    { term = "icons", item = "icon" },
    { term = "health bar", item = "health bar" },
    { term = "power bar", item = "power bar" },
    { term = "mana bar", item = "mana bar" },
    { term = "castbar icon", item = "castbar icon" },
    { term = "cast bar icon", item = "castbar icon" },
    { term = "status icon", item = "status icon" },
    { term = "castbar", item = "castbar" },
    { term = "cast bar", item = "castbar" },
    { term = "portrait", item = "portrait" },
    { term = "name", item = "name" },
    { term = "icon", item = "icon" },
}

local function BooleanItemsFromText(text)
    text = Trim(SingularItem(text or ""))
    if text == "" then return nil end
    local parts = SplitParts(text)
    if parts then
        local out, seen = {}, {}
        for i = 1, #parts do
            local items = BooleanItemsFromText(parts[i])
            if not items then return nil end
            for j = 1, #items do
                if not seen[items[j]] then
                    seen[items[j]] = true
                    out[#out + 1] = items[j]
                end
            end
        end
        return #out > 0 and out or nil
    end

    local rest = Normalize(text)
    local out, seen = {}, {}
    while rest ~= "" do
        local matched
        for i = 1, #BOOLEAN_ITEM_TERMS do
            local spec = BOOLEAN_ITEM_TERMS[i]
            local term = Normalize(spec.term)
            if rest == term or rest:sub(1, #term + 1) == term .. " " then
                matched = spec
                rest = Trim(rest:sub(#term + 1))
                break
            end
        end
        if not matched then return nil end
        if not seen[matched.item] then
            seen[matched.item] = true
            out[#out + 1] = matched.item
        end
    end
    return #out > 0 and out or nil
end

local function ExtractTrailingBoolean(text)
    local words = {}
    for word in Normalize(text):gmatch("%S+") do words[#words + 1] = word end
    if #words < 2 then return nil end
    local verb = BOOL_WORDS[words[#words]]
    if not verb then return nil end
    words[#words] = nil
    return Trim(table.concat(words, " ")), verb
end

local function ExtractLeadingBoolean(text)
    local lead, rest = BooleanLead(text)
    if lead then return rest, lead end
    local words = {}
    for word in Normalize(text):gmatch("%S+") do words[#words + 1] = word end
    if #words < 2 then return nil end
    local verb = BOOL_WORDS[words[1]]
    if not verb then return nil end
    table.remove(words, 1)
    return Trim(table.concat(words, " ")), verb
end

local function AddBooleanScopeItemCommands(commands, verb, scopes, items)
    if #(scopes or {}) == 0 or #(items or {}) == 0 then return false end
    if #scopes * #items > 12 then return false end
    for s = 1, #scopes do
        for i = 1, #items do
            commands[#commands + 1] = Trim(verb .. " " .. scopes[s] .. " " .. items[i])
        end
    end
    return true
end

local BOOLEAN_CHAIN_SCOPE_WORDS = {
    player = true, target = true, focus = true, pet = true, boss = true, party = true, raid = true,
    targettarget = true, focustarget = true,
}

local function NoJoinAlternatingScopeItems(text)
    local words = {}
    for word in Normalize(text):gmatch("%S+") do words[#words + 1] = word end
    local starts = {}
    local i = 1
    while i <= #words do
        if words[i] == "mythic" and words[i + 1] == "raid" then
            starts[#starts + 1] = i
            i = i + 2
        elseif BOOLEAN_CHAIN_SCOPE_WORDS[words[i]] then
            starts[#starts + 1] = i
            i = i + 1
        else
            i = i + 1
        end
    end
    if #starts < 2 then return false end
    for s = 1, #starts - 1 do
        local segment = {}
        for j = starts[s], starts[s + 1] - 1 do segment[#segment + 1] = words[j] end
        if RemoveScopeTerms(table.concat(segment, " ")) ~= "" then return true end
    end
    return false
end

local function BooleanScopeItemList(verb, body)
    body = StripCommandLead(body or "")
    if body == "" then return nil end
    local parts = SplitParts(body)
    if not parts and NoJoinAlternatingScopeItems(body) then return nil end
    local segments = parts or { body }
    local scopes, seenScopes = {}, {}
    local items, seenItems = {}, {}
    local sawScopeOnlyBeforeItem = false
    local leadingMultiScopeItem = false
    local sawItem = false

    for i = 1, #segments do
        local beforeScopeCount = #scopes
        AddScopeLabels(scopes, seenScopes, segments[i])
        local itemList = BooleanItemsFromText(RemoveScopeTerms(segments[i]))
        if itemList then
            sawItem = true
            if i == 1 and (#scopes - beforeScopeCount) >= 2 and #segments > 1 then
                leadingMultiScopeItem = true
            end
            for j = 1, #itemList do
                if not seenItems[itemList[j]] then
                    seenItems[itemList[j]] = true
                    items[#items + 1] = itemList[j]
                end
            end
        elseif not sawItem and #scopes > beforeScopeCount then
            sawScopeOnlyBeforeItem = true
        elseif RemoveScopeTerms(segments[i]) ~= "" then
            return nil
        end
    end
    if #scopes == 0 or #items == 0 then return nil end

    local commands = {}
    if not parts or #scopes == 1 or sawScopeOnlyBeforeItem or leadingMultiScopeItem then
        if not AddBooleanScopeItemCommands(commands, verb, scopes, items) then return nil end
    else
        local lastScopes
        for i = 1, #segments do
            local segmentScopes = ScopeLabels(segments[i])
            if #segmentScopes > 0 then lastScopes = segmentScopes end
            local itemList = BooleanItemsFromText(RemoveScopeTerms(segments[i]))
            if itemList then
                if not AddBooleanScopeItemCommands(commands, verb, (#segmentScopes > 0 and segmentScopes or lastScopes or scopes), itemList) then return nil end
            end
        end
    end
    if #commands < 2 then return nil end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function ExplicitBooleanSegments(text)
    local parts = SplitParts(text)
    if not parts or #parts < 2 then return nil end
    local commands = {}
    for i = 1, #parts do
        local body, verb = ExtractLeadingBoolean(parts[i])
        if not body then body, verb = ExtractTrailingBoolean(parts[i]) end
        if not (body and verb) then
            if i ~= 1 then return nil end
            local plan = SimpleParse(parts[i])
            if not (plan and plan.kind == "changes" and #plan.changes > 0) then return nil end
            commands[#commands + 1] = parts[i]
        else
            commands[#commands + 1] = Trim(verb .. " " .. body)
        end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function BooleanTailItemList(text)
    local body, verb = ExtractTrailingBoolean(text)
    if not (body and verb) then return nil end
    if ContainsAny(body, { " turn on ", " turn off " }) then return nil end
    return BooleanScopeItemList(verb, body)
end

local function BooleanLeadItemList(text)
    local body, verb = ExtractLeadingBoolean(text)
    if not (body and verb) then return nil end
    if ContainsAny(body, { " turn on ", " turn off " }) then return nil end
    return BooleanScopeItemList(verb, body)
end

local function BooleanItemPairs(text)
    local keep = KeepButBoolean(text)
    if keep then return keep end

    local body = StripCommandLead(text)
    if body == "" or body == text and not ContainsAny(text, { " on ", " off " }) then return nil end
    local words = {}
    for word in body:gmatch("%S+") do words[#words + 1] = word end
    local pairsOut = {}
    local start = 1
    for i = 1, #words do
        local verb = BOOL_WORDS[words[i]]
        if verb then
            local segment = {}
            for j = start, i - 1 do segment[#segment + 1] = words[j] end
            local item = SingularItem(table.concat(segment, " "))
            if item == "" then return nil end
            pairsOut[#pairsOut + 1] = { verb = verb, item = item }
            start = i + 1
        end
    end
    if #pairsOut < 2 or start <= #words then return nil end

    local commands = {}
    local firstCommand = Trim(pairsOut[1].verb .. " " .. pairsOut[1].item)
    local firstPlan = SimpleParse(firstCommand)
    if not (firstPlan and firstPlan.kind == "changes" and #firstPlan.changes > 0) then return nil end
    commands[#commands + 1] = firstCommand
    local scope = ScopePhrase(firstPlan.changes)
    if scope == "" then return nil end
    for i = 2, #pairsOut do
        local item = pairsOut[i].item
        if not HasScope(item) then item = Trim(scope .. " " .. item) end
        commands[#commands + 1] = Trim(pairsOut[i].verb .. " " .. item)
    end
    return ParseCommands(commands)
end

local function SharedLeadingScopesItems(text)
    local lead, rest = BooleanLead(text)
    if not lead then return nil end
    local parts = SplitParts(rest)
    if not parts or #parts < 2 then return nil end

    local scopes, seenScopes = {}, {}
    local items, seenItems = {}, {}
    local sawScopeOnlyBeforeItem = false
    local leadingMultiScopeItem = false
    local sawItem = false
    for i = 1, #parts do
        local part = parts[i]
        local beforeScopes = #scopes
        local beforeItems = #items
        AddScopeLabels(scopes, seenScopes, part)
        local item = SingularItem(RemoveScopeTerms(part))
        item = item:gsub("%f[%w]power bars%f[%W]", "power bar")
            :gsub("%f[%w]mana bars%f[%W]", "mana bar")
            :gsub("%f[%w]health bars%f[%W]", "health bar")
            :gsub("%f[%w]hp bars%f[%W]", "hp bar")
            :gsub("%f[%w]castbars%f[%W]", "castbar")
        if item ~= "" then
            sawItem = true
            if not seenItems[item] then
                seenItems[item] = true
                items[#items + 1] = item
            end
        elseif not sawItem and #scopes > 0 then
            sawScopeOnlyBeforeItem = true
        end
        if i == 1 and beforeItems ~= #items then
            if (#scopes - beforeScopes) >= 2 and #parts > 1 then
                leadingMultiScopeItem = true
            else
                return nil
            end
        end
    end
    if #scopes < 2 or #items < 1 or (not sawScopeOnlyBeforeItem and not leadingMultiScopeItem) then return nil end
    if #scopes * #items > 8 then return nil end

    local commands = {}
    for s = 1, #scopes do
        for i = 1, #items do
            commands[#commands + 1] = Trim(lead .. " " .. scopes[s] .. " " .. items[i])
        end
    end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local CHAIN_SCOPE_WORDS = {
    player = true, target = true, focus = true, pet = true, boss = true, party = true, raid = true,
    targettarget = true, focustarget = true,
}

local function BooleanScopeItemChain(text)
    local lead, rest = BooleanLead(text)
    if not lead then return nil end
    if ContainsAny(rest, { "turn on", "turn off", "enable", "disable", "show", "hide" }) then return nil end
    local words = {}
    for word in Normalize(rest):gmatch("%S+") do words[#words + 1] = word end
    local starts = {}
    local i = 1
    while i <= #words do
        if words[i] == "mythic" and words[i + 1] == "raid" then
            starts[#starts + 1] = i
            i = i + 2
        elseif CHAIN_SCOPE_WORDS[words[i]] then
            starts[#starts + 1] = i
            i = i + 1
        else
            i = i + 1
        end
    end
    if #starts < 2 or #starts > 6 then return nil end

    local commands = {}
    for s = 1, #starts do
        local from = starts[s]
        local to = (starts[s + 1] or (#words + 1)) - 1
        local segment = {}
        for j = from, to do segment[#segment + 1] = words[j] end
        local phrase = Trim(table.concat(segment, " "))
        local item = RemoveScopeTerms(phrase)
        if ContainsAny(item, { "on", "off", "enable", "disable", "show", "hide" }) then return nil end
        if item == "" then return nil end
        commands[#commands + 1] = Trim(lead .. " " .. phrase)
    end
    return ParseCommands(commands)
end

local SLOT_WORDS = { left = true, right = true, center = true }

local function CleanSlotValue(text)
    text = Trim(text or "")
    text = text:gsub("^to%s+", ""):gsub("^as%s+", ""):gsub("^is%s+", "")
    text = text:gsub("^auf%s+", ""):gsub("^zu%s+", ""):gsub("^als%s+", "")
    return Trim(text)
end

local function SlotValuePairs(text)
    local words = {}
    for word in Normalize(text):gmatch("%S+") do words[#words + 1] = word end
    local slotIndexes = {}
    for i = 1, #words do
        if SLOT_WORDS[words[i]] then slotIndexes[#slotIndexes + 1] = i end
    end
    if #slotIndexes < 2 or #slotIndexes > 3 then return nil end

    local prefixWords = {}
    for i = 1, slotIndexes[1] - 1 do prefixWords[#prefixWords + 1] = words[i] end
    local prefix = Trim(table.concat(prefixWords, " "))
    if prefix == "" then return nil end
    if not ContainsAny(prefix, { "text", "label" }) then prefix = Trim(prefix .. " text") end
    if not HasStarter(prefix) then prefix = "set " .. prefix end

    local commands = {}
    for i = 1, #slotIndexes do
        local slot = words[slotIndexes[i]]
        local valueWords = {}
        local last = (slotIndexes[i + 1] or (#words + 1)) - 1
        for j = slotIndexes[i] + 1, last do valueWords[#valueWords + 1] = words[j] end
        local value = CleanSlotValue(table.concat(valueWords, " "))
        if value == "" then return nil end
        commands[#commands + 1] = Trim(prefix .. " " .. slot .. " to " .. value)
    end
    return ParseCommands(commands)
end

local DIRECTION_WORDS = { left = true, right = true, up = true, down = true }

local function DirectionPairs(text)
    local words = {}
    for word in Normalize(text):gmatch("%S+") do words[#words + 1] = word end
    local dirs = {}
    local i = 1
    while i <= #words do
        if DIRECTION_WORDS[words[i]] and tonumber(words[i + 1]) ~= nil then
            dirs[#dirs + 1] = { index = i, dir = words[i], amount = words[i + 1], startsWithAmount = false }
            i = i + 2
        elseif tonumber(words[i]) ~= nil and DIRECTION_WORDS[words[i + 1]] then
            dirs[#dirs + 1] = { index = i, dir = words[i + 1], amount = words[i], startsWithAmount = true }
            i = i + 2
        else
            i = i + 1
        end
    end
    if #dirs < 2 or #dirs > 4 then return nil end

    local prefixWords = {}
    for i = 1, dirs[1].index - 1 do prefixWords[#prefixWords + 1] = words[i] end
    local prefix = StripCommandLead(table.concat(prefixWords, " "))
    if prefix == "" then return nil end

    local commands = {}
    for i = 1, #dirs do
        commands[#commands + 1] = Trim("move " .. prefix .. " " .. dirs[i].dir .. " " .. dirs[i].amount)
    end
    return ParseCommands(commands)
end

local function ContextSplit(text)
    local parts = SplitParts(text)
    if not parts then return nil end
    local firstPlan = SimpleParse(parts[1])
    if not (firstPlan and firstPlan.kind == "changes" and type(firstPlan.changes) == "table" and #firstPlan.changes > 0) then return nil end
    local prefix, verb = Prefix(firstPlan)
    local commands = { parts[1] }
    for i = 2, #parts do
        commands[#commands + 1] = SegmentCommand(parts[i], prefix, verb)
        if not commands[#commands] then return nil end
    end
    return ParseCommands(commands)
end

local COLOR_VALUE_WORDS = {
    white = true, black = true, red = true, green = true, blue = true, yellow = true, cyan = true, magenta = true,
    orange = true, purple = true, pink = true, turquoise = true, grey = true, gray = true, brown = true, gold = true,
    violet = true, aqua = true, teal = true,
    weiss = true, schwarz = true, rot = true, gruen = true, blau = true, gelb = true, lila = true, rosa = true, tuerkis = true,
}

local FONT_MODE_VALUE_WORDS = {
    default = true, palette = true, class = true, health = true, hp = true, resource = true, power = true, npc = true, red = true,
}

local SHAPE_VALUE_WORDS = { square = true, circle = true, round = true, rounded = true, diamond = true }
local BORDER_VALUE_WORDS = { none = true, off = true, hide = true, hidden = true, disabled = true, solid = true, class = true, reaction = true, custom = true }

local function Words(text)
    local out = {}
    for word in Normalize(text):gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function WordsText(words, first, last)
    if not words or not first or not last or last < first then return "" end
    return table.concat(words, " ", first, last)
end

local function SegmentHasAny(words, first, last, phrases)
    return ContainsAny(WordsText(words, first, last), phrases)
end

local function ValueTokenLength(words, index, segmentStart)
    local word = words and words[index]
    if not word then return 0 end
    local nextWord = words[index + 1]
    if word == "class" and nextWord == "color" and SegmentHasAny(words, segmentStart, index + 1, {
        "portrait border", "border", "name color", "name text color",
    }) then
        return 2
    end
    if (word == "reaction" or word == "custom") and nextWord == "color" and SegmentHasAny(words, segmentStart, index + 1, {
        "portrait border", "border",
    }) then
        return 2
    end
    if COLOR_VALUE_WORDS[word] and SegmentHasAny(words, segmentStart, index, { "color", "colour", "tint", "farbe" }) then
        return 1
    end
    if SHAPE_VALUE_WORDS[word] and SegmentHasAny(words, segmentStart, index, { "portrait shape", "shape" }) then
        return 1
    end
    if BORDER_VALUE_WORDS[word] and SegmentHasAny(words, segmentStart, index, { "portrait border", "border" }) then
        return 1
    end
    if FONT_MODE_VALUE_WORDS[word] and SegmentHasAny(words, segmentStart, index, {
        "name color", "name text color", "hp text color", "health text color", "power text color", "mana text color",
        "resource text color", "npc name color", "npc text color",
    }) then
        return 1
    end
    return 0
end

local function ValueTokenSegments(text)
    local words = Words((text or ""):gsub("=", " "))
    if #words < 4 or #words > 48 then return nil end
    local segments = {}
    local startIndex = 1
    local i = 1
    while i <= #words do
        local len = ValueTokenLength(words, i, startIndex)
        if len > 0 then
            local last = i + len - 1
            segments[#segments + 1] = WordsText(words, startIndex, last)
            startIndex = last + 1
            i = startIndex
        else
            i = i + 1
        end
    end
    if #segments < 2 or startIndex <= #words then return nil end
    return segments
end

local function StartsWithAny(text, phrases)
    text = Normalize(text)
    for i = 1, #(phrases or {}) do
        local phrase = Normalize(phrases[i])
        if text == phrase or text:sub(1, #phrase + 1) == phrase .. " " then return true end
    end
    return false
end

local function ValueChainCommand(segment, prefix, verb)
    segment = Trim(segment):gsub("^and%s+", ""):gsub("^und%s+", "")
    segment = Trim(segment)
    if segment == "" then return nil end
    if HasStarter(segment) then return segment end
    if HasScope(segment) then return Trim(tostring(verb or "set") .. " " .. segment) end
    if StartsWithAny(segment, {
        "bar", "bars", "bar background", "castbar", "cast bar", "class resource", "combat", "global",
    }) then
        return Trim(tostring(verb or "set") .. " " .. segment)
    end
    local normalizedPrefix = Normalize(prefix)
    if StartsWithAny(segment, { "portrait" }) and ContainsAny(normalizedPrefix, { "portrait" }) then
        segment = Trim(segment:gsub("^portrait%s+", ""))
    end
    return SegmentCommand(segment, prefix, verb)
end

local function ValueTokenChain(text)
    local segments = ValueTokenSegments(text)
    if not segments then return nil end
    local firstPlan = SimpleParse(segments[1])
    if not (firstPlan and firstPlan.kind == "changes" and type(firstPlan.changes) == "table" and #firstPlan.changes > 0) then return nil end
    local prefix, verb = Prefix(firstPlan)
    local commands = { segments[1] }
    for i = 2, #segments do
        local command = ValueChainCommand(segments[i], prefix, verb)
        if not command then return nil end
        commands[#commands + 1] = command
    end
    return ParseCommands(commands)
end

local function CountNumbers(text)
    local count = 0
    for _ in tostring(text or ""):gmatch("[-+]?%d+%.?%d*") do
        count = count + 1
        if count >= 2 then return count end
    end
    return count
end

local function CountKnownWords(text, words)
    local count = 0
    for word in Normalize(text):gmatch("%S+") do
        if words[word] then
            count = count + 1
            if count >= 2 then return count end
        end
    end
    return count
end

local function HasTrailingBooleanMultiScope(text)
    local body = ExtractTrailingBoolean(text)
    return body and #ScopeLabels(body) >= 2
end

local function LooksLikeCompoundCandidate(text, hasJoin)
    if hasJoin then return true end
    if CountNumbers(text) >= 2 then return true end
    if text:find("%d+%.?%d*%s*x%s*%d+%.?%d*") or text:find("%d+%.?%d*%s+by%s+%d+%.?%d*") then return true end
    if text:find(" but ", 1, true) then return true end
    if CountKnownWords(text, BOOL_WORDS) >= 2 then return true end
    if CountKnownWords(text, SLOT_WORDS) >= 2 then return true end
    local lead, rest = BooleanLead(text)
    if lead and #ScopeLabels(rest) >= 2 then return true end
    if HasTrailingBooleanMultiScope(text) then return true end
    if CountNumbers(text) == 1 and #ScopeLabels(text) >= 2 and ContainsAny(text, {
        "width", "widths", "height", "heights", "x offset", "x offsets", "y offset", "y offsets",
    }) then return true end
    if CountNumbers(text) == 1 and ContainsAny(text, { "portrait shape", "border thickness", "border size", "background on", "background off" }) then return true end
    if ValueTokenSegments(text) then return true end
    return false
end

function P.ParseCompound(normalized, raw, normalParsed)
    if (tonumber(P._compoundDepth) or 0) > 0 then return nil end
    local text = SafeText(raw ~= "" and raw or normalized)
    if text == "" or ShouldSkip(text) then return nil end
    if #text > 240 then return nil end
    if normalParsed and normalParsed.kind ~= "changes" and normalParsed.kind ~= "ambiguous" and normalParsed.kind ~= "unknown" then return nil end

    local hasJoin = text:find(" and ", 1, true) or text:find(" und ", 1, true)
    if not LooksLikeCompoundCandidate(text, hasJoin) then return nil end
    local normalCount = ChangeCount(normalParsed)
    local noJoinCommands = (not hasJoin) and NoJoinScopeItemCommands(text) or nil
    local candidates = {}
    local function add(candidate)
        if candidate then candidates[#candidates + 1] = candidate end
    end
    add(MultiSizePairs(text))
    add(SizePair(text))
    add(AttributeListValues(text))
    add(AttributeListTrailingNumbers(text))
    add(AttributeListRelativeValues(text))
    add(SharedAttributeValue(text))
    add(SharedAttributeRelativeValue(text))
    add(ScopedValueTailPairs(text))
    add(ScopedRelativeValueTailPairs(text))
    add(AttributeNumberPairs(text))
    add(HybridSizeTail(text))
    add(ValueTokenChain(text))
    add(SlotValuePairs(text))
    add(DirectionPairs(text))
    add(ExplicitBooleanSegments(text))
    add(BooleanTailItemList(text))
    add(BooleanLeadItemList(text))
    add(BooleanItemPairs(text))
    add(SharedLeadingScopesItems(text))
    add(BooleanScopeItemChain(text))
    add(SharedScopeValue(text))
    add(SharedScopeRelativeValue(text))
    if noJoinCommands then add(ParseCommands(noJoinCommands)) end
    if hasJoin then
        local parts = SplitParts(text)
        local trailing = parts and TrailingScopeItemCommands(parts) or nil
        if trailing then add(ParseCommands(trailing)) end
        add(SharedValue(text))
        add(SharedScope(text))
        add(ContextSplit(text))
    end
    local best
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate and (candidate.compoundForce == true
            or ChangeCount(candidate) > math.max(1, normalCount)
            or (ChangeCount(candidate) >= 2 and ChangeCount(candidate) == normalCount and PlanSignature(candidate) ~= PlanSignature(normalParsed))) then
            if not best or ChangeCount(candidate) > ChangeCount(best) then best = candidate end
        end
    end
    return best
end
