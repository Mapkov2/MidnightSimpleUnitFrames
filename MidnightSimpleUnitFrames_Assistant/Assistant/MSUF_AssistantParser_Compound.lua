--- Shell/Menu2/Assistant/MSUF_AssistantParser_Compound.lua
--- Compound command parser for multi-change Assistant input.
---
--- Splits one natural sentence into declarative child plans and yields between
--- chunks so bulk parsing keeps the same confirmation, undo, and budget rules.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P
local Registry = A.Registry
local Trim = P.Trim
local Normalize = P.Normalize
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local ExtractColor = P.ExtractColor
local Data = A.ParserData or {}
A.ParserData = Data
local CompoundData = Data.COMPOUND_PARSER or {}

local function MaybeYield()
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
end

local COMMAND_STARTERS = CompoundData.COMMAND_STARTERS or {}
local SKIP_TERMS = CompoundData.SKIP_TERMS or {}
local VALUE_CONNECTORS = CompoundData.VALUE_CONNECTORS or {}
local RELATIVE_VALUE_CONNECTORS = CompoundData.RELATIVE_VALUE_CONNECTORS or {}
local SCOPE_RELATIONS = CompoundData.SCOPE_RELATIONS or {}

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
    return not ContainsAny(text, CompoundData.SKIP_ALLOW_TERMS)
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
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
    }
end

local function SimpleParse(text)
    text = Trim(text)
    if text == "" then return nil end
    local cache = P._compoundSimpleParseCache
    local cacheKey
    if type(cache) == "table" then
        cacheKey = Normalize(text)
        local cached = cache[cacheKey]
        if cached ~= nil then return cached ~= false and cached or nil end
    end
    local parsed
    if type(A.ParseSimpleChange) == "function" then
        P._compoundDepth = (tonumber(P._compoundDepth) or 0) + 1
        parsed = A.ParseSimpleChange(text)
        P._compoundDepth = math.max(0, (tonumber(P._compoundDepth) or 1) - 1)
    else
        P._compoundDepth = (tonumber(P._compoundDepth) or 0) + 1
        parsed = A.Parse(text)
        P._compoundDepth = math.max(0, (tonumber(P._compoundDepth) or 1) - 1)
    end
    if type(cache) == "table" and cacheKey then cache[cacheKey] = parsed or false end
    return parsed
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
    return (#units + #groups) > 0 or ContainsAny(text, CompoundData.BROAD_SCOPE_TERMS)
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
    for _, lead in ipairs({ "deaktivieren", "deaktiviere", "ausschalten", "verstecken", "verstecke", "ausblenden" }) do
        if text:sub(1, #lead + 1) == lead .. " " then return "turn off", Trim(text:sub(#lead + 2)) end
    end
    for _, lead in ipairs({ "aktivieren", "aktiviere", "einschalten", "anzeigen", "zeige", "einblenden" }) do
        if text:sub(1, #lead + 1) == lead .. " " then return "turn on", Trim(text:sub(#lead + 2)) end
    end
    return nil, text
end

local function SingularItem(text)
    return Trim((text or "")
        :gsub("%f[%w]names%f[%W]", "name")
        :gsub("%f[%w]namen%f[%W]", "name")
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
        { label = "target of target", terms = { "targettarget", "target of target", "tot", "ziel des ziels" } },
        { label = "focus target", terms = { "focustarget", "focus target", "fokus ziel" } },
    }
    for i = 1, #explicitUnits do
        if ContainsAny(tail, explicitUnits[i].terms) then add(explicitUnits[i].label) end
    end
    if ContainsAny(tail, CompoundData.PARTY_TERMS) then add("party") end
    local hasMythicRaid = ContainsAny(tail, CompoundData.MYTHIC_RAID_TERMS)
    if hasMythicRaid then add("mythic raid") end
    if not hasMythicRaid and ContainsAny(tail, CompoundData.RAID_TERMS) then add("raid") end
    local units = DetectUnits(tail)
    for i = 1, #units do add(units[i]) end
    local groups = DetectGroups(tail)
    for i = 1, #groups do
        local group = groups[i] == "mythicraid" and "mythic raid" or groups[i]
        add(group)
    end
    return out
end

local SCOPE_REMOVE_TERMS = CompoundData.SCOPE_REMOVE_TERMS or {}

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
    for _, lead in ipairs({
        "set", "change", "make", "turn", "show", "hide", "enable", "disable", "increase", "decrease", "raise", "lower",
        "setze", "stelle", "mach", "mache", "schalte", "schalt", "aktiviere", "deaktiviere", "zeige", "verstecke"
    }) do
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

local ATTR_SPECS = CompoundData.ATTR_SPECS or {}

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

local function LeadingNumberList(text, wanted)
    wanted = tonumber(wanted)
    if not wanted or wanted <= 0 then return nil end
    local words = {}
    for word in Normalize(text or ""):gmatch("%S+") do words[#words + 1] = word end
    local values = {}
    local i = 1
    while i <= #words and #values < wanted do
        local word = words[i]
        if word:match("^[-+]?%d+%.?%d*$") then
            values[#values + 1] = word
        elseif word == "and" or word == "und" or word == "to" or word == "as" or word == "is" or word == "be"
            or word == "value" or word == "auf" or word == "zu" or word == "als" or word == "wert" or word == "=" then
            -- connector between list values
        else
            return nil
        end
        i = i + 1
    end
    if #values ~= wanted then return nil end
    local tail = {}
    for j = i, #words do tail[#tail + 1] = words[j] end
    tail = Trim(table.concat(tail, " "))
    tail = tail:gsub("^and%s+", ""):gsub("^und%s+", "")
    return values, Trim(tail)
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

local AddScopedBooleanTailCommands
local function AttributeListValues(text)
    local s = LastConnector(text, VALUE_CONNECTORS)
    if not s then return nil end
    local body = Trim(text:sub(1, s - 1))
    if body:find("[-+]?%d+%.?%d*") then return nil end
    local prefix, attrs = AttributeListPrefix(body)
    if not prefix or prefix == "" or not attrs or #attrs < 2 or #attrs > 6 then return nil end
    local values, tail = LeadingNumberList(text:sub(s), #attrs)
    if not values then return nil end

    local commands = {}
    for i = 1, #attrs do
        if not AddScopedAttributeCommands(commands, StripCommandLead(prefix), attrs[i], values[i]) then return nil end
    end
    if tail ~= "" and not AddScopedBooleanTailCommands(commands, StripCommandLead(prefix), tail) then return nil end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function AttributeListTrailingNumbers(text)
    local pairText = Normalize((text or ""):gsub("=", " "))
    local s = pairText:find("[-+]?%d+%.?%d*")
    if not s then return nil end
    local body = Trim(pairText:sub(1, s - 1))
    local prefix, attrs = AttributeListPrefix(body)
    if not prefix or prefix == "" or not attrs or #attrs < 2 or #attrs > 6 then return nil end
    local values, tail = LeadingNumberList(pairText:sub(s), #attrs)
    if not values then return nil end

    local commands = {}
    for i = 1, #attrs do
        if not AddScopedAttributeCommands(commands, StripCommandLead(prefix), attrs[i], values[i]) then return nil end
    end
    if tail ~= "" and not AddScopedBooleanTailCommands(commands, StripCommandLead(prefix), tail) then return nil end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function StripAttributeListBlockLead(text)
    text = Trim(text or "")
    while true do
        local before = text
        text = text:gsub("^and%s+", ""):gsub("^und%s+", ""):gsub("^then%s+", ""):gsub("^dann%s+", "")
        text = Trim(text)
        if text == before then break end
    end
    return text
end

local function RepeatedAttributeListTrailingNumbers(text)
    local rest = Normalize((text or ""):gsub("=", " "))
    local commands = {}
    local touchedScopes, seenTouchedScopes = {}, {}
    local blocks = 0
    while rest ~= "" do
        rest = StripAttributeListBlockLead(rest)
        if rest == "" then break end
        local s = rest:find("[-+]?%d+%.?%d*")
        if not s then
            if blocks < 2 then return nil end
            local scope = table.concat(touchedScopes, " ")
            if #ScopeLabels(rest) > 0 or #touchedScopes <= 1 or not ContainsAny(rest, CompoundData.AMBIGUOUS_TAIL_ITEMS) then
                scope = touchedScopes[#touchedScopes] or scope
            end
            if scope == "" or not AddScopedBooleanTailCommands(commands, scope, rest) then return nil end
            rest = ""
            break
        end

        local body = Trim(rest:sub(1, s - 1))
        local prefix, attrs = AttributeListPrefix(body)
        if not prefix or prefix == "" or not attrs or #attrs < 2 or #attrs > 6 then return nil end
        local values, tail = LeadingNumberList(rest:sub(s), #attrs)
        if not values then return nil end

        local scope = StripCommandLead(prefix)
        if scope == "" then return nil end
        AddScopeLabels(touchedScopes, seenTouchedScopes, scope)
        for i = 1, #attrs do
            if not AddScopedAttributeCommands(commands, scope, attrs[i], values[i]) then return nil end
        end
        blocks = blocks + 1
        if blocks > 4 then return nil end
        rest = tail
    end

    if blocks < 2 then return nil end
    local plan = ParseCommands(commands)
    if plan then plan.compoundForce = true end
    return plan
end

local function DetailScopeForAttr(scope, attr)
    scope = Trim(scope or "")
    attr = Normalize(attr or "")
    if scope == "" then return "" end
    if attr:sub(1, 8) == "portrait" and not ContainsAny(scope, CompoundData.PORTRAIT_SCOPE_TERMS) then
        return Trim(scope .. " portrait")
    end
    if (attr:sub(1, 7) == "hp text" or attr:sub(1, 11) == "health text") and not ContainsAny(scope, CompoundData.HP_TEXT_SCOPE_TERMS) then
        return Trim(scope .. " hp text")
    end
    if attr:sub(1, 10) == "power text" and not ContainsAny(scope, CompoundData.POWER_TEXT_SCOPE_TERMS) then
        return Trim(scope .. " power text")
    end
    return scope
end

local function AttributeNamesDetailScope(attr)
    attr = Normalize(attr or "")
    return attr:match("^portrait%s+") ~= nil
        or attr:match("^hp%s+text%s+") ~= nil
        or attr:match("^health%s+text%s+") ~= nil
        or attr:match("^power%s+text%s+") ~= nil
end

local function LooksLikeOnlyScopes(text)
    return text ~= "" and HasScope(text) and RemoveScopeTerms(text) == ""
end

local function DistributableScopePrefixes(scope)
    scope = Trim(scope or "")
    local scopes = ScopeLabels(scope)
    if #scopes <= 1 then return nil end
    local detail = RemoveScopeTerms(scope)
    if detail ~= "" and not ContainsAny(detail, CompoundData.DISTRIBUTABLE_DETAIL_TERMS) then
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
    if ContainsAny(text, CompoundData.BOOL_OFF_TERMS) then return "turn off" end
    if ContainsAny(text, CompoundData.BOOL_ON_TERMS) then return "turn on" end
    return nil
end

-- Split an explicit two-clause boolean sentence without losing the polarity
-- carried by "keep" or by a negated second verb. Normalization removes the
-- apostrophe in "don't", so handle both normalized English forms here.
local function ButBooleanClauses(text)
    text = Normalize(text)
    local first, second = text:match("^(.-)%s+but%s+keep%s+(.+)$")
    if first then
        local explicitVerb = BooleanVerbForText(second)
        return first, second, explicitVerb, explicitVerb == nil
    end
    first, second = text:match("^(.-)%s+but%s+leave%s+(.+)$")
    if first then
        local explicitVerb = BooleanVerbForText(second)
        return first, second, explicitVerb, explicitVerb == nil
    end

    local negated
    first, negated = text:match("^(.-)%s+but%s+dont%s+(.+)$")
    if not first then first, negated = text:match("^(.-)%s+but%s+do%s+not%s+(.+)$") end
    if first then
        local verb, body = BooleanLead(negated)
        if verb == "turn on" then return first, body, "turn off" end
        if verb == "turn off" then return first, body, "turn on" end
        return nil
    end

    first, second = text:match("^(.-)%s+but%s+(.+)$")
    if not first then return nil end
    local verb, body = BooleanLead(second)
    if not verb then return nil end
    return first, body, verb
end

local function StripBooleanWords(text)
    local out = " " .. Normalize(text) .. " "
    for _, word in ipairs({ "on", "off", "enable", "enabled", "disable", "disabled", "true", "false", "yes", "no", "show", "hide", "visible", "hidden", "keep", "and", "und", "for" }) do
        out = out:gsub(" " .. word .. " ", " ")
    end
    return SingularItem(Normalize(out))
end

local function BooleanWordVerb(word)
    if word == "on" or word == "enable" or word == "enabled" or word == "true" or word == "yes" or word == "show" then return "turn on" end
    if word == "off" or word == "disable" or word == "disabled" or word == "false" or word == "no" or word == "hide" then return "turn off" end
    return nil
end

local BOOLEAN_TAIL_ITEM_TERMS = CompoundData.BOOLEAN_TAIL_ITEM_TERMS or {}

local function BooleanTailItemsFromText(text)
    text = SingularItem(Normalize(text or ""))
    text = text:gsub("%f[%w]power bars%f[%W]", "power bar")
        :gsub("%f[%w]mana bars%f[%W]", "mana bar")
        :gsub("%f[%w]health bars%f[%W]", "health bar")
        :gsub("%f[%w]hp bars%f[%W]", "hp bar")
        :gsub("%f[%w]castbars%f[%W]", "castbar")
    if text == "" then return nil end
    local parts = SplitParts(text)
    if parts then
        local out, seen = {}, {}
        for i = 1, #parts do
            local items = BooleanTailItemsFromText(parts[i])
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

    local out, seen = {}, {}
    local rest = text
    while rest ~= "" do
        local matched
        for i = 1, #BOOLEAN_TAIL_ITEM_TERMS do
            local spec = BOOLEAN_TAIL_ITEM_TERMS[i]
            local term = spec.term
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

local function BooleanTailPairs(tail)
    local words = {}
    for word in Normalize(tail):gmatch("%S+") do words[#words + 1] = word end
    local out, segment = {}, {}
    for i = 1, #words do
        local word = words[i]
        if word == "and" or word == "und" then
            -- connector between pairs
        else
            local verb = BooleanWordVerb(word)
            if verb then
                local item = Trim(table.concat(segment, " "))
                if item == "" then return nil end
                out[#out + 1] = { verb = verb, item = item }
                segment = {}
            else
                segment[#segment + 1] = word
            end
        end
    end
    if #out == 0 or #segment > 0 then return nil end
    return out
end

local function BooleanRelationScope(text)
    local item, scoped = text:match("^(.-)%s+for%s+(.+)$")
    if item and scoped and #ScopeLabels(scoped) > 0 then return Trim(item), Trim(scoped) end
    return text, nil
end

local function ParentBooleanScopes(scope)
    scope = StripCommandLead(scope or "")
    if scope == "" then return nil end
    return DistributableScopePrefixes(scope) or (LooksLikeOnlyScopes(scope) and ScopeLabels(scope) or nil) or { scope }
end

local function AddScopedBooleanItemCommands(commands, verb, scopes, itemText)
    local items = BooleanTailItemsFromText(StripBooleanWords(itemText))
    if not items or #(scopes or {}) == 0 then return false end
    if #items * #scopes > 12 then return false end
    for s = 1, #scopes do
        for i = 1, #items do
            commands[#commands + 1] = Trim(verb .. " " .. scopes[s] .. " " .. items[i])
        end
    end
    return true
end

AddScopedBooleanTailCommands = function(commands, scope, tail)
    local pairs = BooleanTailPairs(tail)
    if pairs and #pairs > 1 then
        for i = 1, #pairs do
            if not AddScopedBooleanTailCommands(commands, scope, pairs[i].item .. " " .. (pairs[i].verb == "turn on" and "on" or "off")) then return false end
        end
        return true
    end

    local verb = BooleanVerbForText(tail)
    if not verb then return false end
    local itemText, relationScope = BooleanRelationScope(tail)
    local scopes = ScopeLabels(relationScope or tail)
    if #scopes > 0 then
        itemText = RemoveScopeTerms(itemText)
    else
        scopes = ParentBooleanScopes(scope)
    end
    return AddScopedBooleanItemCommands(commands, verb, scopes, itemText)
end

local function FastSettingChange(changes, scope, attr, rawValue)
    scope = Normalize(scope or "")
    if scope == "mythic raid" then scope = "mythicraid" end
    local dbScope = scope
    if scope == "party" then dbScope = "gf_party" end
    if scope == "raid" then dbScope = "gf_raid" end
    if scope == "mythicraid" then dbScope = "gf_mythicraid" end
    local settingKey, value
    if attr == "width" or attr == "height" then
        settingKey = dbScope .. "." .. attr
        value = tonumber(rawValue)
    elseif attr == "power bar height" then
        if dbScope == "gf_party" or dbScope == "gf_raid" or dbScope == "gf_mythicraid" then
            settingKey = dbScope .. ".powerHeight"
        else
            settingKey = dbScope .. ".powerBarHeight"
        end
        value = tonumber(rawValue)
    elseif attr == "alpha" then
        settingKey = dbScope .. ".hpBarAlpha"
        value = tonumber(rawValue)
        if value and value > 1 then value = value / 100 end
    else
        return false
    end
    local setting = Registry and Registry.GetSetting and Registry:GetSetting(settingKey)
    if not (setting and value ~= nil) then return false end
    changes[#changes + 1] = { setting = setting, value = value }
    return true
end

local function FastBooleanChange(changes, scope, item, verb)
    scope = Normalize(scope or "")
    if scope == "mythic raid" then scope = "mythicraid" end
    local dbScope = scope
    if scope == "party" then dbScope = "gf_party" end
    if scope == "raid" then dbScope = "gf_raid" end
    if scope == "mythicraid" then dbScope = "gf_mythicraid" end
    local on = verb == "turn on"
    local settingKey, value
    item = SingularItem(Normalize(item or ""))
    if item == "name" then
        settingKey = dbScope .. ".showName"
        value = on
    elseif item == "portrait" then
        settingKey = dbScope .. ".portraitMode"
        value = on and "LEFT" or "OFF"
    elseif item == "power bar" or item == "mana bar" then
        settingKey = dbScope .. ".showPowerBar"
        value = on
    elseif item == "power text" then
        settingKey = dbScope .. ".showPowerText"
        value = on
    elseif item == "health text" then
        settingKey = dbScope .. ".showHPText"
        value = on
    elseif item == "buff" or item == "debuff" then
        local lane = item
        if dbScope == "gf_party" or dbScope == "gf_raid" or dbScope == "gf_mythicraid" then
            settingKey = dbScope .. ".auras." .. lane .. ".enabled"
        else
            settingKey = "auras3." .. dbScope .. "." .. lane .. ".visible"
        end
        value = on
    else
        return false
    end
    local setting = Registry and Registry.GetSetting and Registry:GetSetting(settingKey)
    if not setting then return false end
    changes[#changes + 1] = { setting = setting, value = value }
    return true
end

local function FastBooleanItemsForText(text)
    return BooleanTailItemsFromText(StripBooleanWords(RemoveScopeTerms(text)))
        or BooleanTailItemsFromText(StripBooleanWords(text))
end

local function FastApplyBooleanItems(changes, scopes, items, verb)
    if #(scopes or {}) == 0 or #(items or {}) == 0 then return false end
    if #scopes * #items > 16 then return false end
    for s = 1, #scopes do
        for i = 1, #items do
            if not FastBooleanChange(changes, scopes[s], items[i], verb) then return false end
        end
    end
    return true
end

local function FastKeepBoolean(text)
    local first, second, secondVerb, retainSecond = ButBooleanClauses(text)
    if not (first and second and (secondVerb or retainSecond)) then return nil end

    local firstVerb, firstBody = BooleanLead(first)
    if not firstVerb then return nil end

    local secondItemText, relationScope = BooleanRelationScope(second)
    local secondScopes = ScopeLabels(relationScope or second)
    if #secondScopes > 0 then secondItemText = RemoveScopeTerms(secondItemText) end
    local firstScopes = ScopeLabels(firstBody)
    if #firstScopes == 0 then firstScopes = secondScopes end
    if #secondScopes == 0 then secondScopes = firstScopes end
    if #firstScopes == 0 or #secondScopes == 0 then return nil end

    local firstItems = FastBooleanItemsForText(firstBody)
    local secondItems = FastBooleanItemsForText(secondItemText)
    if not (firstItems and secondItems) then return nil end

    local changes = {}
    if not FastApplyBooleanItems(changes, firstScopes, firstItems, firstVerb) then return nil end
    if not retainSecond and not FastApplyBooleanItems(changes, secondScopes, secondItems, secondVerb) then return nil end
    if #changes < (retainSecond and 1 or 2) then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
        compoundForce = true,
        compoundRetainsSecond = retainSecond and true or nil,
    }
end

local function FastBooleanScopeList(text)
    local verb, body = BooleanLead(text)
    if not verb then return nil end
    if BooleanVerbForText(body) ~= nil then return nil end
    local scopes = ScopeLabels(body)
    if #scopes == 0 then return nil end
    local items = FastBooleanItemsForText(body)
    if not items or #items == 0 then return nil end
    if #items > 1 then return nil end
    local changes = {}
    if not FastApplyBooleanItems(changes, scopes, items, verb) then return nil end
    if #changes < 2 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
        compoundForce = true,
    }
end

local function FastNumericBooleanChain(text)
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
    if #values < 2 or #values > 8 then return nil end

    local changes, currentScopes = {}, nil
    local touchedScopes, seenTouchedScopes = {}, {}
    for i = 1, #values do
        local prefix, attr = ExtractAttr(segments[i])
        if not attr or (attr ~= "width" and attr ~= "height" and attr ~= "alpha" and attr ~= "power bar height") then return nil end
        prefix = StripCommandLead(prefix or "")
        prefix = Trim(prefix:gsub("^and$", ""):gsub("^und$", "")
            :gsub("^and%s+", ""):gsub("^und%s+", ""))
        if RemoveScopeTerms(prefix) ~= "" then return nil end
        if prefix ~= "" then
            local scopes = ScopeLabels(prefix)
            if #scopes == 0 then return nil end
            currentScopes = scopes
        elseif not currentScopes then
            return nil
        end
        for s = 1, #currentScopes do
            if not FastSettingChange(changes, currentScopes[s], attr, values[i]) then return nil end
        end
        AddScopeLabels(touchedScopes, seenTouchedScopes, table.concat(currentScopes, " "))
    end

    if tail ~= "" then
        local pairs = BooleanTailPairs(tail)
        if pairs and #pairs > 1 then
            for i = 1, #pairs do
                local items = BooleanTailItemsFromText(StripBooleanWords(pairs[i].item))
                if not items then return nil end
                for s = 1, #touchedScopes do
                    for itemIndex = 1, #items do
                        if not FastBooleanChange(changes, touchedScopes[s], items[itemIndex], pairs[i].verb) then return nil end
                    end
                end
            end
        else
            local verb = BooleanVerbForText(tail)
            if not verb then return nil end
            local itemText, relationScope = BooleanRelationScope(tail)
            local scopes = ScopeLabels(relationScope or tail)
            if #scopes > 0 then
                itemText = RemoveScopeTerms(itemText)
            else
                scopes = touchedScopes
            end
            local items = BooleanTailItemsFromText(StripBooleanWords(itemText))
            if not items then return nil end
            for s = 1, #scopes do
                for itemIndex = 1, #items do
                    if not FastBooleanChange(changes, scopes[s], items[itemIndex], verb) then return nil end
                end
            end
        end
    end

    if #changes < 2 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
        compoundForce = true,
    }
end

local function FastApplyBooleanTail(changes, scopes, tail)
    tail = Normalize(tail or "")
    if tail == "" then return true end
    local tailPairs = BooleanTailPairs(tail)
    if tailPairs and #tailPairs > 1 then
        for i = 1, #tailPairs do
            local items = BooleanTailItemsFromText(StripBooleanWords(tailPairs[i].item))
            if not items then return false end
            for s = 1, #scopes do
                for itemIndex = 1, #items do
                    if not FastBooleanChange(changes, scopes[s], items[itemIndex], tailPairs[i].verb) then return false end
                end
            end
        end
        return true
    end

    local verb = BooleanVerbForText(tail)
    if not verb then return false end
    local itemText, relationScope = BooleanRelationScope(tail)
    local tailScopes = ScopeLabels(relationScope or tail)
    if #tailScopes > 0 then
        itemText = RemoveScopeTerms(itemText)
    else
        tailScopes = scopes
    end
    local items = BooleanTailItemsFromText(StripBooleanWords(itemText))
    return FastApplyBooleanItems(changes, tailScopes, items, verb)
end

local function FastAttributeListTrailingNumbers(text)
    local rest = Normalize((text or ""):gsub("=", " "))
    local changes = {}
    local touchedScopes, seenTouchedScopes = {}, {}
    local blocks = 0
    while rest ~= "" do
        rest = StripAttributeListBlockLead(rest)
        if rest == "" then break end
        local s = rest:find("[-+]?%d+%.?%d*")
        if not s then
            if blocks < 1 then return nil end
            local scopeText = table.concat(touchedScopes, " ")
            if #ScopeLabels(rest) > 0 or #touchedScopes <= 1 or not ContainsAny(rest, CompoundData.AMBIGUOUS_TAIL_ITEMS_SHORT) then
                scopeText = touchedScopes[#touchedScopes] or scopeText
            end
            local scopes = ScopeLabels(scopeText)
            if #scopes == 0 or not FastApplyBooleanTail(changes, scopes, rest) then return nil end
            rest = ""
            break
        end

        local body = Trim(rest:sub(1, s - 1))
        local prefix, attrs = AttributeListPrefix(body)
        if not prefix or prefix == "" or not attrs or #attrs < 2 or #attrs > 4 then return nil end
        local values, tail = LeadingNumberList(rest:sub(s), #attrs)
        if not values then return nil end

        local scopeText = StripCommandLead(prefix)
        local scopes = ScopeLabels(scopeText)
        if #scopes == 0 then return nil end
        AddScopeLabels(touchedScopes, seenTouchedScopes, scopeText)
        for i = 1, #attrs do
            local attr = attrs[i]
            if attr ~= "width" and attr ~= "height" and attr ~= "alpha" then return nil end
            for scopeIndex = 1, #scopes do
                if not FastSettingChange(changes, scopes[scopeIndex], attr, values[i]) then return nil end
            end
        end
        blocks = blocks + 1
        if blocks > 4 then return nil end
        rest = tail
    end

    if #changes < 2 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
        compoundForce = true,
    }
end

local function BooleanScopeText(text)
    local _, relationScope = BooleanRelationScope(text)
    local scopes = ScopeLabels(relationScope or text)
    return #scopes > 0 and table.concat(scopes, " ") or nil
end

local function BooleanCommandsForText(verb, body, fallbackScope)
    local commands = {}
    local itemText, relationScope = BooleanRelationScope(body)
    local scopes = ScopeLabels(relationScope or body)
    if #scopes > 0 then
        itemText = RemoveScopeTerms(itemText)
    elseif fallbackScope then
        scopes = ScopeLabels(fallbackScope)
    end
    if not AddScopedBooleanItemCommands(commands, verb, scopes, itemText) then return nil end
    return commands
end

local function ScopeTextFromCommandList(commands)
    local scopes, seen = {}, {}
    for i = 1, #(commands or {}) do AddScopeLabels(scopes, seen, commands[i]) end
    return #scopes > 0 and table.concat(scopes, " ") or nil
end

local function AppendCommands(commands, more)
    for i = 1, #(more or {}) do commands[#commands + 1] = more[i] end
end

local function PrefixPrePlanAllowedForAttribute(prePlan, prefix, attr)
    if not (prePlan and type(prePlan.changes) == "table") then return false end
    attr = tostring(attr or "")
    if (attr == "width" or attr == "height")
        and ContainsAny(prefix, CompoundData.CASTBAR_TERMS)
        and #prePlan.changes == 1 then
        local setting = prePlan.changes[1] and prePlan.changes[1].setting
        if setting and setting.frameType == "castbar" and setting.attribute == "iconBorderStyle" then
            return false
        end
    end
    if ContainsAny(prefix, CompoundData.POWER_BAR_TERMS)
        and not ContainsAny(prefix, CompoundData.SHAPE_STYLE_TERMS)
        and #prePlan.changes == 1 then
        local setting = prePlan.changes[1] and prePlan.changes[1].setting
        if setting and setting.attribute == "detachedPowerBarShape" then
            return false
        end
    end
    return true
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
    local touchedScopes, seenTouchedScopes = {}, {}
    for i = 1, #values do
        local rawSegment = segments[i]
        local prefix, attr = ExtractAttr(rawSegment)
        if not attr then return nil end
        local rawPrefix = prefix
        local prePlan
        if i == 1 and prefix and prefix ~= "" then
            prePlan = SimpleParse(prefix)
            if not (prePlan and prePlan.kind == "changes" and type(prePlan.changes) == "table" and #prePlan.changes > 0) then prePlan = nil end
            if prePlan and not PrefixPrePlanAllowedForAttribute(prePlan, prefix, attr) then prePlan = nil end
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
        if i == 1 and AttributeNamesDetailScope(attr) then
            scope = firstPrefix
        end
        if not usedPrePlan and prefix ~= "" and HasScope(prefix) then
            scope = prefix
            currentScope = DetailScopeForAttr(prefix, attr)
        elseif prefix == "" and currentScope ~= "" and not attr:find("portrait", 1, true) and not attr:find("hp text", 1, true) and not attr:find("power text", 1, true) then
            scope = currentScope
        end
        AddScopeLabels(touchedScopes, seenTouchedScopes, scope)
        if not AddScopedAttributeCommands(commands, scope, attr, values[i]) then return nil end
    end
    if tail ~= "" then
        local scope = detailScope ~= "" and detailScope or firstPrefix
        if #ScopeLabels(tail) == 0 and #touchedScopes > 1 and ContainsAny(tail, CompoundData.AMBIGUOUS_TAIL_ITEMS) then
            scope = table.concat(touchedScopes, " ")
        end
        if not AddScopedBooleanTailCommands(commands, scope, tail) then return nil end
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
    if ContainsAny(text, CompoundData.RELATIVE_INCREASE_TERMS) then return "increase" end
    if ContainsAny(text, CompoundData.RELATIVE_DECREASE_TERMS) then return "decrease" end
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
        local nextPrefix, nextAttr = ExtractAttr(scope)
        if nextAttr then
            nextPrefix = StripCommandLead(nextPrefix or "")
            local nextScope = nextPrefix ~= "" and nextPrefix or firstPrefix
            if not AddScopedRelativeAttributeCommands(commands, lead, nextScope, nextAttr, values[i]) then return nil end
        else
        if not LooksLikeOnlyScopes(scope) then return nil end
        local scopes = ScopeLabels(scope)
        if #scopes == 0 then return nil end
        for s = 1, #scopes do
            commands[#commands + 1] = Trim(lead .. " " .. scopes[s] .. " " .. attr .. " by " .. tostring(values[i]))
        end
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
    return (#units + #groups) > 0 or ContainsAny(tail, CompoundData.SCOPE_TAIL_CONCRETE_TERMS)
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
    local first, second, secondVerb, retainSecond = ButBooleanClauses(text)
    if not (first and second and (secondVerb or retainSecond)) then return nil end
    local firstLead, firstBody = BooleanLead(first)
    if not firstLead then return nil end
    local fallbackScope = BooleanScopeText(second)
    local firstCommands = BooleanCommandsForText(firstLead, firstBody, fallbackScope)
    if not firstCommands then return nil end
    local firstScope = ScopeTextFromCommandList(firstCommands) or fallbackScope
    local secondCommands = not retainSecond and BooleanCommandsForText(secondVerb, second, firstScope) or nil
    if not retainSecond and not secondCommands then return nil end
    local commands = {}
    AppendCommands(commands, firstCommands)
    if secondCommands then AppendCommands(commands, secondCommands) end
    local plan = ParseCommands(commands)
    if plan and retainSecond then
        plan.compoundForce = true
        plan.compoundRetainsSecond = true
    end
    return plan
end

local BOOL_WORDS = CompoundData.BOOL_WORDS or {}

local BOOLEAN_ITEM_TERMS = CompoundData.BOOLEAN_ITEM_TERMS or {}

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
    return StripCommandLead(Trim(table.concat(words, " "))), verb
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

local BOOLEAN_CHAIN_SCOPE_WORDS = CompoundData.BOOLEAN_CHAIN_SCOPE_WORDS or {}

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
    if ContainsAny(body, CompoundData.BOOLEAN_TOGGLE_GUARD_TERMS) then return nil end
    return BooleanScopeItemList(verb, body)
end

local function BooleanLeadItemList(text)
    local body, verb = ExtractLeadingBoolean(text)
    if not (body and verb) then return nil end
    if ContainsAny(body, CompoundData.BOOLEAN_TOGGLE_GUARD_TERMS) then return nil end
    return BooleanScopeItemList(verb, body)
end

local function BooleanItemPairs(text)
    local keep = KeepButBoolean(text)
    if keep then return keep end

    local body = StripCommandLead(text)
    if body == "" or body == text and not ContainsAny(text, CompoundData.BOOLEAN_ON_OFF_TERMS) then return nil end
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
    local scope
    for i = 1, #pairsOut do
        local item = pairsOut[i].item
        if HasScope(item) then
            local labels = ScopeLabels(item)
            if #labels > 0 then scope = table.concat(labels, " ") end
        end
        if not AddScopedBooleanTailCommands(commands, scope, item .. " " .. (pairsOut[i].verb == "turn on" and "on" or "off")) then return nil end
    end
    if #commands < 2 then return nil end
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

local CHAIN_SCOPE_WORDS = CompoundData.CHAIN_SCOPE_WORDS or {}

local function BooleanScopeItemChain(text)
    local lead, rest = BooleanLead(text)
    if not lead then return nil end
    if ContainsAny(rest, CompoundData.BOOLEAN_COMMAND_TERMS) then return nil end
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
        if ContainsAny(item, CompoundData.BOOLEAN_ITEM_REJECT_TERMS) then return nil end
        if item == "" then return nil end
        commands[#commands + 1] = Trim(lead .. " " .. phrase)
    end
    return ParseCommands(commands)
end

local SLOT_WORDS = CompoundData.SLOT_WORDS or {}

local function StripImplicitSlotVisibility(plan)
    if not (plan and plan.kind == "changes" and type(plan.changes) == "table") then return plan end
    local hasSlotChange = false
    for i = 1, #plan.changes do
        local attr = tostring(plan.changes[i].setting and plan.changes[i].setting.attribute or "")
        if attr == "hpTextLeft" or attr == "hpTextCenter" or attr == "hpTextRight"
            or attr == "healthTextLeft" or attr == "healthTextCenter" or attr == "healthTextRight"
            or attr == "powerTextLeft" or attr == "powerTextCenter" or attr == "powerTextRight"
        then
            hasSlotChange = true
            break
        end
    end
    if not hasSlotChange then return plan end
    local filtered = {}
    for i = 1, #plan.changes do
        local change = plan.changes[i]
        local attr = tostring(change.setting and change.setting.attribute or "")
        local implicitEnable = change.value == true and (attr == "hpText" or attr == "powerText")
        if not implicitEnable then filtered[#filtered + 1] = change end
    end
    plan.changes = filtered
    return plan
end

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
    if not ContainsAny(prefix, CompoundData.TEXT_LABEL_TERMS) then prefix = Trim(prefix .. " text") end
    if not HasStarter(prefix) then prefix = "set " .. prefix end

    -- A later slot may begin a new scoped text block ("player ... left
    -- current target ... right percent"). In that form this same-prefix
    -- parser would absorb the second scope into the first value and fabricate
    -- extra changes; RepeatedSlotValueBlocks owns the scoped form instead.
    for i = 1, #slotIndexes - 1 do
        local between = {}
        for j = slotIndexes[i] + 1, slotIndexes[i + 1] - 1 do between[#between + 1] = words[j] end
        local betweenText = table.concat(between, " ")
        if #ScopeLabels(betweenText) > 0 and ContainsAny(betweenText, CompoundData.TEXT_LABEL_TERMS) then
            return nil
        end
    end

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
    return StripImplicitSlotVisibility(ParseCommands(commands))
end

local function SlotWords(text)
    local out = {}
    for word in Normalize(text):gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function SlotWordsText(words, first, last)
    if not words or not first or not last or last < first then return "" end
    return table.concat(words, " ", first, last)
end

local function SlotBlockStart(words, index)
    if not words or not index or index > #words then return false end
    local start = index
    if words[start] == "and" or words[start] == "und" or words[start] == "then" or words[start] == "dann" then
        start = start + 1
    end
    local slotIndex
    for i = start, math.min(#words, start + 6) do
        if SLOT_WORDS[words[i]] then
            slotIndex = i
            break
        end
    end
    if not slotIndex or slotIndex <= start then return false end
    local prefix = SlotWordsText(words, start, slotIndex - 1)
    return HasScope(prefix) and ContainsAny(prefix, CompoundData.TEXT_LABEL_TERMS)
end

local function SkipSlotBlockLead(words, index)
    while index <= #words and (words[index] == "and" or words[index] == "und" or words[index] == "then" or words[index] == "dann") do
        index = index + 1
    end
    return index
end

local function RepeatedSlotValueBlocks(text)
    local words = SlotWords(StripCommandLead(text or ""))
    if #words < 8 or #words > 64 then return nil end
    local commands = {}
    local blocks = 0
    local index = 1
    while index <= #words do
        index = SkipSlotBlockLead(words, index)
        if index > #words then break end
        if not SlotBlockStart(words, index) then return nil end

        local slotIndex
        for i = index, #words do
            if SLOT_WORDS[words[i]] then
                slotIndex = i
                break
            end
        end
        if not slotIndex then return nil end
        local prefix = SlotWordsText(words, index, slotIndex - 1)
        if prefix == "" or not ContainsAny(prefix, CompoundData.TEXT_LABEL_TERMS) or not HasScope(prefix) then return nil end
        blocks = blocks + 1
        if blocks > 5 then return nil end

        index = slotIndex
        while index <= #words and SLOT_WORDS[words[index]] do
            local slot = words[index]
            local valueStart = index + 1
            local valueEnd = valueStart
            while valueEnd <= #words do
                if SLOT_WORDS[words[valueEnd]] then break end
                if valueEnd > valueStart and SlotBlockStart(words, valueEnd) then break end
                valueEnd = valueEnd + 1
            end
            local value = CleanSlotValue(SlotWordsText(words, valueStart, valueEnd - 1))
            if value == "" then return nil end
            commands[#commands + 1] = Trim("set " .. prefix .. " " .. slot .. " to " .. value)
            index = valueEnd
        end
    end

    if blocks < 2 or #commands < 2 then return nil end
    local plan = StripImplicitSlotVisibility(ParseCommands(commands))
    if plan then plan.compoundForce = true end
    return plan
end

local DIRECTION_WORDS = CompoundData.DIRECTION_WORDS or {}

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

local COLOR_VALUE_WORDS = CompoundData.COLOR_VALUE_WORDS or {}

local FONT_MODE_VALUE_WORDS = CompoundData.FONT_MODE_VALUE_WORDS or {}

local SHAPE_VALUE_WORDS = CompoundData.SHAPE_VALUE_WORDS or {}
local BORDER_VALUE_WORDS = CompoundData.BORDER_VALUE_WORDS or {}

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
    if StartsWithAny(segment, CompoundData.PORTRAIT_SCOPE_TERMS) and ContainsAny(normalizedPrefix, CompoundData.PORTRAIT_SCOPE_TERMS) then
        segment = Trim(segment:gsub("^portrait%s+", ""))
    end
    return SegmentCommand(segment, prefix, verb)
end

local ScopedColorSegmentPlan

local function ValueTokenChain(text)
    local segments = ValueTokenSegments(text)
    if not segments then return nil end
    local firstPlan = (ScopedColorSegmentPlan and ScopedColorSegmentPlan(segments[1])) or SimpleParse(segments[1])
    if not (firstPlan and firstPlan.kind == "changes" and type(firstPlan.changes) == "table" and #firstPlan.changes > 0) then return nil end
    local prefix, verb = Prefix(firstPlan)
    local plans = { firstPlan }
    for i = 2, #segments do
        local command = ValueChainCommand(segments[i], prefix, verb)
        if not command then return nil end
        local plan = (ScopedColorSegmentPlan and ScopedColorSegmentPlan(command)) or SimpleParse(command)
        if not (plan and plan.kind == "changes" and type(plan.changes) == "table" and #plan.changes > 0) then return nil end
        plans[#plans + 1] = plan
    end
    return MergePlans(plans)
end

local function FastBarScope(scope)
    scope = Normalize(scope or "")
    if scope == "mythic raid" or scope == "mythicraid" or scope == "raid" then return "gf_raid" end
    if scope == "party" then return "gf_party" end
    return scope
end

ScopedColorSegmentPlan = function(segment)
    local words = Words(segment)
    if #words < 4 then return nil end
    local colorWord = words[#words]
    if not COLOR_VALUE_WORDS[colorWord] then return nil end
    local r, g, b, label
    if type(ExtractColor) == "function" then
        r, g, b, label = ExtractColor(colorWord, colorWord)
    end
    if not r then return nil end

    local prefix = StripCommandLead(WordsText(words, 1, #words - 1))
    local detail = RemoveScopeTerms(prefix)
    local changes = {}
    if detail == "border color"
        or detail == "outline color"
        or detail == "bar border color"
        or detail == "bar outline color"
        or detail == "frame border color"
        or detail == "frame outline color" then
        local scopes = ScopeLabels(prefix)
        if #scopes == 0 then return nil end
        for scopeIndex = 1, #scopes do
            local setting = Registry and Registry.GetSetting and Registry:GetSetting("barScope." .. FastBarScope(scopes[scopeIndex]) .. ".barOutlineColor")
            if not setting then return nil end
            changes[#changes + 1] = {
                setting = setting,
                value = { r = r, g = g, b = b, label = label },
                valueLabel = label,
            }
        end
    elseif detail == "bar background color"
        or detail == "bar background tint"
        or detail == "class bar background color"
        or detail == "class bar background tint" then
        if #ScopeLabels(prefix) > 0 then return nil end
        local setting = Registry and Registry.GetSetting and Registry:GetSetting("general.classBarBgColor")
        if not setting then return nil end
        changes[#changes + 1] = {
            setting = setting,
            value = { r = r, g = g, b = b, label = label },
            valueLabel = label,
        }
    else
        return nil
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
    }
end

local function FastScopedBorderColorChain(text)
    local segments = ValueTokenSegments(text)
    if not segments then return nil end
    local changes = {}
    for i = 1, #segments do
        local words = Words(segments[i])
        if #words < 4 then return nil end
        local colorWord = words[#words]
        if not COLOR_VALUE_WORDS[colorWord] then return nil end
        local r, g, b, label
        if type(ExtractColor) == "function" then
            r, g, b, label = ExtractColor(colorWord, colorWord)
        end
        if not r then return nil end

        local prefix = StripCommandLead(WordsText(words, 1, #words - 1))
        local detail = RemoveScopeTerms(prefix)
        if detail ~= "border color"
            and detail ~= "outline color"
            and detail ~= "bar border color"
            and detail ~= "bar outline color"
            and detail ~= "frame border color"
            and detail ~= "frame outline color" then
            return nil
        end
        local scopes = ScopeLabels(prefix)
        if #scopes == 0 then return nil end
        for scopeIndex = 1, #scopes do
            local setting = Registry and Registry.GetSetting and Registry:GetSetting("barScope." .. FastBarScope(scopes[scopeIndex]) .. ".barOutlineColor")
            if not setting then return nil end
            changes[#changes + 1] = {
                setting = setting,
                value = { r = r, g = g, b = b, label = label },
                valueLabel = label,
            }
        end
    end
    if #changes < 2 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Combined Assistant option changes",
        summary = "Applies several requested option changes.",
        bulkSafe = true,
        compoundForce = true,
    }
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
    if ContainsAny(text, CompoundData.AURA_FILTER_TERMS) and ContainsAny(text, CompoundData.AURA_KIND_TERMS) then return false end
    if hasJoin then return true end
    if CountNumbers(text) >= 2 then return true end
    if text:find("%d+%.?%d*%s*x%s*%d+%.?%d*") or text:find("%d+%.?%d*%s+by%s+%d+%.?%d*") then return true end
    if text:find(" but ", 1, true) then return true end
    if CountKnownWords(text, BOOL_WORDS) >= 2 then return true end
    if CountKnownWords(text, SLOT_WORDS) >= 2 then return true end
    local lead, rest = BooleanLead(text)
    if lead and #ScopeLabels(rest) >= 2 then return true end
    if HasTrailingBooleanMultiScope(text) then return true end
    if CountNumbers(text) == 1 and #ScopeLabels(text) >= 2 and ContainsAny(text, CompoundData.MULTISCOPE_NUMERIC_ATTR_TERMS) then return true end
    if CountNumbers(text) == 1 and ContainsAny(text, CompoundData.SINGLE_NUMBER_SPECIAL_TERMS) then return true end
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
    local previousSimpleParseCache = P._compoundSimpleParseCache
    P._compoundSimpleParseCache = {}
    local function finish(result)
        P._compoundSimpleParseCache = previousSimpleParseCache
        return result
    end
    local normalCount = ChangeCount(normalParsed)
    local normalSignature
    local function accepted(candidate)
        local count = ChangeCount(candidate)
        if count <= 0 then return false, count end
        if candidate.compoundForce == true or count > math.max(1, normalCount) then return true, count end
        if count >= 2 and count == normalCount then
            normalSignature = normalSignature or PlanSignature(normalParsed)
            return PlanSignature(candidate) ~= normalSignature, count
        end
        return false, count
    end

    if text:find(" but ", 1, true) then
        local keep = FastKeepBoolean(text) or KeepButBoolean(text)
        local ok, count = accepted(keep)
        if ok and (count >= 2 or keep.compoundRetainsSecond == true) then return finish(keep) end
    end

    local fastBoolean = FastBooleanScopeList(text)
    local fastBooleanOk, fastBooleanCount = accepted(fastBoolean)
    if fastBooleanOk and fastBooleanCount >= 2 then return finish(fastBoolean) end

    local numberCount = CountNumbers(text)
    local function acceptedNumeric(candidate)
        if not candidate then return nil end
        local ok, count = accepted(candidate)
        if ok and count >= 2 then return candidate end
        return nil
    end
    if numberCount >= 2 then
        local numeric = acceptedNumeric(FastNumericBooleanChain(text))
            or acceptedNumeric(ScopedValueTailPairs(text))
            or acceptedNumeric(ScopedRelativeValueTailPairs(text))
            or acceptedNumeric(FastAttributeListTrailingNumbers(text))
            or acceptedNumeric(RepeatedAttributeListTrailingNumbers(text))
            or acceptedNumeric(AttributeNumberPairs(text))
            or acceptedNumeric(AttributeListTrailingNumbers(text))
            or acceptedNumeric(AttributeListValues(text))
        if numeric then return finish(numeric) end
    elseif numberCount == 1 then
        local numeric = acceptedNumeric(AttributeNumberPairs(text))
            or acceptedNumeric(AttributeListTrailingNumbers(text))
            or acceptedNumeric(AttributeListValues(text))
        if numeric then return finish(numeric) end
    end

    if CountKnownWords(text, COLOR_VALUE_WORDS) >= 2 then
        local color = FastScopedBorderColorChain(text)
        local ok, count = accepted(color)
        if ok and count >= 2 then return finish(color) end
    end

    local noJoinCommands = (not hasJoin) and NoJoinScopeItemCommands(text) or nil
    local candidates = {}
    local function add(candidate)
        if candidate then candidates[#candidates + 1] = candidate end
    end
    add(MultiSizePairs(text))
    add(SizePair(text))
    add(AttributeListValues(text))
    add(AttributeListTrailingNumbers(text))
    MaybeYield()
    add(RepeatedAttributeListTrailingNumbers(text))
    add(AttributeListRelativeValues(text))
    add(SharedAttributeValue(text))
    add(SharedAttributeRelativeValue(text))
    MaybeYield()
    add(ScopedValueTailPairs(text))
    add(ScopedRelativeValueTailPairs(text))
    add(AttributeNumberPairs(text))
    add(HybridSizeTail(text))
    MaybeYield()
    add(ValueTokenChain(text))
    add(RepeatedSlotValueBlocks(text))
    add(SlotValuePairs(text))
    add(DirectionPairs(text))
    MaybeYield()
    add(ExplicitBooleanSegments(text))
    add(BooleanTailItemList(text))
    add(BooleanLeadItemList(text))
    add(BooleanItemPairs(text))
    MaybeYield()
    add(SharedLeadingScopesItems(text))
    add(BooleanScopeItemChain(text))
    add(SharedScopeValue(text))
    add(SharedScopeRelativeValue(text))
    MaybeYield()
    if noJoinCommands then add(ParseCommands(noJoinCommands)) end
    if hasJoin then
        local parts = SplitParts(text)
        local trailing = parts and TrailingScopeItemCommands(parts) or nil
        if trailing then add(ParseCommands(trailing)) end
        MaybeYield()
        add(SharedValue(text))
        add(SharedScope(text))
        add(ContextSplit(text))
    end
    local best
    for i = 1, #candidates do
        if i % 4 == 0 then MaybeYield() end
        local candidate = candidates[i]
        if candidate and accepted(candidate) then
            if not best or ChangeCount(candidate) > ChangeCount(best) then best = candidate end
        end
    end
    return finish(best)
end
