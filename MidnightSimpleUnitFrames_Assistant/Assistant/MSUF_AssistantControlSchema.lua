--- Lazy Assistant control-schema access and safe execution facade.
--- The generated data is built on desktop across every class/spec context;
--- this runtime never constructs hidden Menu2 pages or installs passive work.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ControlSchemaData or {}
local Schema = A.ControlSchema or {}
A.ControlSchema = Schema

local index
local searchCache = {}
local searchOrder = {}
local SEARCH_CACHE_LIMIT = 24
local STOP = {
    a=true, an=true, ["and"]=true, are=true, can=true, ["do"]=true, find=true, ["for"]=true, how=true, i=true,
    ["in"]=true, is=true, it=true, me=true, my=true, of=true, on=true, option=true, please=true, setting=true,
    show=true, hide=true, help=true, frame=true, the=true, to=true, where=true, with=true, set=true, change=true, make=true, turn=true, ["on"]=true, off=true,
    enable=true, disable=true, enabled=true, disabled=true, open=true, close=true, current=true, value=true,
    bitte=true, das=true, der=true, die=true, einstellung=true, finde=true, fuer=true, ich=true,
    ist=true, kann=true, mir=true, mich=true, option=true, wo=true, zeige=true, zu=true, setze=true, stelle=true,
    aktivieren=true, deaktivieren=true, einschalten=true, ausschalten=true, oeffne=true,
    start=true, starts=true, started=true, starting=true, begin=true, launch=true, run=true, play=true,
    stop=true, stops=true, stopping=true, ["end"]=true, toggle=true, switch=true, try=true,
    take=true, go=true, navigate=true, jump=true, direct=true, lead=true, bring=true, exact=true,
    control=true, slider=true, checkbox=true, dropdown=true, picker=true,
    what=true, why=true, explain=true, describe=true, tell=true, about=true, list=true, all=true, every=true,
    available=true, choice=true, choices=true, values=true, configured=true, currently=true,
    starte=true, starten=true, startest=true, stoppe=true, stoppen=true, beende=true, beenden=true,
    gehe=true, navigiere=true, springe=true, fuehre=true, bringe=true, direkt=true, regler=true,
    -- Conversational filler. A player writes "can you make the border thicker",
    -- not "border thickness"; every one of these words would otherwise become a
    -- required search token that no control can ever contain, which drops the
    -- whole query to zero hits.
    you=true, your=true, we=true, us=true, our=true, would=true, could=true, should=true,
    want=true, wants=true, need=true, needs=true, like=true, just=true, now=true,
    ["then"]=true, this=true, that=true, these=true, those=true, there=true, here=true,
    be=true, been=true, being=true, get=true, got=true, have=true, has=true, had=true,
    into=true, from=true, at=true, as=true, by=true, ["or"]=true, ["but"]=true, ["if"]=true,
    so=true, its=true, im=true, ive=true, id=true, ill=true, lets=true, let=true, ok=true, okay=true,
    thanks=true, thank=true, hey=true, hi=true, hello=true, msuf=true,
    -- Measurement units. "2 pixels" and "2" name the same value; the unit word
    -- is never part of a control's identity.
    pixel=true, pixels=true, px=true, percent=true, percentage=true, pct=true,
}

local TOKEN_ALIASES = {
    vorschau = "preview", vorschauen = "preview", testmodus = "test", testmodi = "test",
    indikator = "indicator", indikatoren = "indicators", statusanzeige = "status indicator",
    zauberleiste = "castbar", zauberleisten = "castbars", absorbtion = "absorb",
    vorhersage = "prediction", balken = "bars", rahmen = "frame",
}

local function Trim(value)
    value = tostring(value or "")
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(value)
    value = Trim(value):lower()
    value = value:gsub("ä", "ae"):gsub("ö", "oe"):gsub("ü", "ue"):gsub("ß", "ss")
    return (value:gsub("[^%w]+", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Control labels are written in the singular ("Border thickness"), players ask
-- in the plural ("set the borders to 2"). Index text is searched with plain
-- find, so folding the query token down to its singular stem also still matches
-- a plural label ("border" is inside "Highlight Borders"); folding the other way
-- would not. Deliberately conservative: -ss/-us/-is/-as never lose their s, so
-- "class", "status" and "bias" survive intact.
local function Singular(token)
    local length = #token
    if length < 4 or token:sub(-1) ~= "s" then return token end
    if length >= 5 and token:sub(-3) == "ies" then return token:sub(1, length - 3) .. "y" end
    local tail4 = token:sub(-4)
    if length >= 6 and (tail4 == "sses" or tail4 == "shes" or tail4 == "ches") then
        return token:sub(1, length - 2)
    end
    local tail3 = token:sub(-3)
    if length >= 5 and (tail3 == "xes" or tail3 == "zes") then return token:sub(1, length - 2) end
    local tail2 = token:sub(-2)
    if tail2 == "ss" or tail2 == "us" or tail2 == "is" or tail2 == "as" then return token end
    return token:sub(1, length - 1)
end

-- Returns the singular stems used for matching AND the words as written.
-- Folding is what lets "borders" find "Border thickness", but it must never be
-- allowed to erase a distinction: two settings whose names differ only by a
-- trailing "s" fold to the same stem, and treating them as one would let a
-- request for either silently land on the other. The exact forms keep them
-- apart -- they decide identity, while the stems only decide reach.
local function SearchTokenPairs(value)
    local stems, exacts = {}, {}
    for token in Normalize(value):gmatch("%S+") do
        local alias = TOKEN_ALIASES[token] or token
        for normalizedToken in tostring(alias):gmatch("%S+") do
            local stem = Singular(normalizedToken)
            if not STOP[normalizedToken] and not STOP[stem] and not normalizedToken:match("^%-?%d") then
                stems[#stems + 1] = stem
                exacts[#exacts + 1] = normalizedToken
            end
        end
    end
    return stems, exacts
end

local function SearchTokens(value)
    return (SearchTokenPairs(value))
end

local function ExactTokenKey(value)
    local _, exacts = SearchTokenPairs(value)
    return table.concat(exacts, "\031")
end

-- Pages whose identity IS the scope. Two rows that share a control path on two
-- of these pages are two different frames' controls and must never be merged.
-- Every other page is a menu location for a surface whose scope lives inside
-- the control path, so the same path there really is the same stored value.
local SCOPE_PAGES = {
    uf_player = true, uf_target = true, uf_focus = true, uf_pet = true,
    uf_targettarget = true, uf_focustarget = true, uf_boss = true,
}

-- Longest first: "target of target" has to be claimed before the bare "target"
-- inside it can be. The index is searched with plain find, where "target" also
-- sits inside "targettarget" and "focustarget", so without this a request about
-- the Target frame ranks Target of Target's controls first.
local UNIT_PAGE_ALIASES = {
    { alias = " target of target ", page = "uf_targettarget" },
    { alias = " targettarget ", page = "uf_targettarget" },
    { alias = " focus target ", page = "uf_focustarget" },
    { alias = " focustarget ", page = "uf_focustarget" },
    { alias = " player ", page = "uf_player" },
    { alias = " target ", page = "uf_target" },
    { alias = " focus ", page = "uf_focus" },
    { alias = " pet ", page = "uf_pet" },
    { alias = " boss ", page = "uf_boss" },
}

-- Which unit frames did the request actually name? Nil means "no unit named",
-- which leaves every page eligible.
local function NamedUnitPages(paddedQuery)
    local scan, named = paddedQuery, nil
    for i = 1, #UNIT_PAGE_ALIASES do
        local row = UNIT_PAGE_ALIASES[i]
        if scan:find(row.alias, 1, true) then
            named = named or {}
            named[row.page] = true
            -- Consume it so "target of target" cannot also register "target".
            scan = scan:gsub(row.alias, " ")
        end
    end
    return named
end

-- Words that name a family of frames rather than a control. They steer ranking
-- but must not be required search tokens: "unitframe border" has to find the
-- unit pages' Border controls, whose indexed text never spells "unitframe".
local SCOPE_TOKENS = {
    unitframe = "uf_", unitframes = "uf_", groupframe = "gf_", groupframes = "gf_",
    partyframe = "gf_", partyframes = "gf_", raidframe = "gf_", raidframes = "gf_",
}

local function SearchTokenKey(value)
    return table.concat(SearchTokens(value), "\031")
end

local function CanonicalSearchText(row)
    return table.concat({ row and row.label or "", row and row.pageKey or "", row and row.controlPath or "" }, " ")
end

local CANONICAL_QUERY_PREFIXES = {
    "take me to ", "navigate to ", "direct me to ", "bring me to ", "jump to ",
    "show me ", "where is ", "go to ", "open ", "find ",
    "fuehre mich zu ", "zeige mir ", "oeffne ", "finde ", "wo ist ",
}

local function CanonicalIdentityQuery(value)
    local normalized = Normalize(value)
    for i = 1, #CANONICAL_QUERY_PREFIXES do
        local prefix = CANONICAL_QUERY_PREFIXES[i]
        if normalized:sub(1, #prefix) == prefix then return normalized:sub(#prefix + 1) end
    end
    return normalized
end

local function CurrentContextId()
    local classToken = ""
    if type(UnitClass) == "function" then
        local _, token = UnitClass("player")
        classToken = tostring(token or "")
    end
    local specId
    if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
        specId = select(1, GetSpecializationInfo(GetSpecialization()))
    end
    return classToken ~= "" and specId and (classToken .. "-" .. tostring(specId)) or ""
end

local function Available(row, contextId)
    local contexts = tostring(row and row.contexts or "")
    if contexts == "*" then return true end
    contextId = contextId or CurrentContextId()
    if contextId == "" then return false end
    return ("," .. contexts .. ","):find("," .. contextId .. ",", 1, true) ~= nil
end

local function StateAvailable(row, stateId)
    if not stateId or stateId == "" then return true end
    local states = tostring(row and row.states or "")
    if states == "*" then return true end
    return ("," .. states .. ","):find("," .. tostring(stateId) .. ",", 1, true) ~= nil
end

local function DecodeValues(value)
    local out = {}
    for encoded in tostring(value or ""):gmatch("[^\031]+") do
        local typed, label = encoded:match("^(.-)\030(.*)$")
        if typed then
            local prefix, raw = typed:match("^(%a):(.*)$")
            local decoded = raw
            if prefix == "b" then decoded = raw == "1"
            elseif prefix == "n" then decoded = tonumber(raw) end
            out[#out + 1] = { value = decoded, text = label ~= "" and label or raw }
        end
    end
    return out
end

local function DecodeLength(text, position, limit)
    local colon = text:find(":", position, true)
    if not colon or colon > limit then return nil, position, "missing_length" end
    local raw = text:sub(position, colon - 1)
    if raw == "" or not raw:match("^%d+$") then return nil, position, "invalid_length" end
    return tonumber(raw), colon + 1
end

local DecodeCanonicalAt
DecodeCanonicalAt = function(text, position, limit, stopAtEquals)
    position, limit = tonumber(position) or 1, tonumber(limit) or #text
    if position > limit then return nil, position, "missing_value" end
    local tag = text:sub(position, position)
    if tag == "b" then
        local bit = text:sub(position + 1, position + 1)
        if bit ~= "0" and bit ~= "1" then return nil, position, "invalid_boolean" end
        return bit == "1", position + 2
    end
    if tag == "n" then
        local finish = limit
        if stopAtEquals then
            local equals = text:find("=", position + 1, true)
            if equals and equals <= limit then finish = equals - 1 end
        end
        local raw = text:sub(position + 1, finish)
        local value = tonumber(raw)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            return nil, position, "invalid_number"
        end
        return value, finish + 1
    end
    if tag == "s" then
        local length, payloadStart, err = DecodeLength(text, position + 1, limit)
        if not length then return nil, position, err end
        local payloadEnd = payloadStart + length - 1
        if payloadEnd > limit then return nil, position, "truncated_string" end
        return text:sub(payloadStart, payloadEnd), payloadEnd + 1
    end
    if tag == "t" then
        local count, cursor, err = DecodeLength(text, position + 1, limit)
        if not count then return nil, position, err end
        local out = {}
        for _ = 1, count do
            local rowLength, rowStart, rowErr = DecodeLength(text, cursor, limit)
            if not rowLength then return nil, position, rowErr end
            local rowEnd = rowStart + rowLength - 1
            if rowEnd > limit then return nil, position, "truncated_table_row" end
            local key, afterKey, keyErr = DecodeCanonicalAt(text, rowStart, rowEnd, true)
            if keyErr then return nil, position, keyErr end
            if text:sub(afterKey, afterKey) ~= "=" then return nil, position, "missing_table_separator" end
            local child, afterChild, childErr = DecodeCanonicalAt(text, afterKey + 1, rowEnd, false)
            if childErr then return nil, position, childErr end
            if afterChild ~= rowEnd + 1 then return nil, position, "trailing_table_value" end
            if type(key) ~= "string" and type(key) ~= "number" then return nil, position, "invalid_table_key" end
            if out[key] ~= nil then return nil, position, "duplicate_table_key" end
            out[key] = child
            cursor = rowEnd + 1
        end
        return out, cursor
    end
    return nil, position, "unknown_type"
end

local function DecodeCanonicalData(value)
    value = tostring(value or "")
    if value == "" then return nil end
    local decoded, position, err = DecodeCanonicalAt(value, 1, #value, false)
    if err or position ~= #value + 1 then return nil, err or "trailing_data" end
    return decoded
end

Schema.DecodeCanonicalData = DecodeCanonicalData

local function CopyRecord(row)
    if type(row) ~= "table" then return nil end
    local out = {}
    local columns = index and index.columns or Data.columns or {}
    for column = 1, #columns do out[columns[column]] = row[column] end
    -- Keep compatibility with focused fixtures that hand a descriptor to this
    -- helper as an associative table. Generated rows remain compact arrays.
    if #columns == 0 then for key, value in pairs(row) do out[key] = value end end
    out.values = DecodeValues(row.values)
    out.actionFixedArgs = DecodeCanonicalData(row.actionFixedArgs)
    out.actionInputDomain = DecodeCanonicalData(row.actionInputDomain)
    out.available = Available(row)
    local Registry = A.Registry
    local setting = row.settingKey and row.settingKey ~= "" and Registry
        and type(Registry.GetSetting) == "function" and Registry:GetSetting(row.settingKey) or nil
    if setting and setting.percent == true then
        -- Direct schema values use the Registry's native fractional domain.
        -- Callers that intentionally provide display percentages must opt in
        -- with opts.inputUnit="percent"; conversational parsing already does
        -- the display-to-storage conversion before execution.
        out.storageUnit = "fraction"
        out.displayUnit = "percent"
        out.displayScale = 100
    end
    return out
end

-- Lowercase once, on the first row that actually needs it.
local function LazyLower(cache, index, value)
    local cached = cache[index]
    if cached == nil then
        cached = tostring(value or ""):lower()
        cache[index] = cached
    end
    return cached
end

local function EnsureIndex()
    if index then return index end
    local columns = Data.columns or {}
    local columnIndex = {}
    for c = 1, #columns do columnIndex[columns[c]] = c end
    local rowMeta = { __index = function(row, key)
        local column = columnIndex[key]
        if column then return rawget(row, column) end
    end }
    local built = {
        bySemanticId = {}, bySettingKey = {}, byControlId = {},
        rows = Data.records or {}, columns = columns,
        search = {}, labelSearch = {}, pageSearch = {}, valueSearch = {},
        labelTokenKey = {}, labelTokens = {}, canonicalIdentityKey = {},
        rowMeta = rowMeta,
    }
    for i = 1, #(Data.records or {}) do
        local row = Data.records[i]
        setmetatable(row, rowMeta)
        built.search[i] = table.concat({ row.label or "", row.help or "", row.semanticId or "",
            row.settingKey or "", row.actionKey or "", row.pageKey or "", row.controlPath or "", row.values or "" }, " "):lower()
        -- label/page/value strings are only ever consulted for a row whose
        -- combined text already matched a token, which is a small fraction of
        -- the catalog. Building all three for every row tripled the cold index
        -- cost for nothing; they are filled in on demand below instead.
        -- Label-token and canonical-identity keys are needed only for rows
        -- that match a query.  Computing them for the entire 2k+ catalog made
        -- the first ordinary search pay for thousands of unused normalizations.
        built.bySemanticId[row.semanticId] = row
        if row.controlId ~= "" then built.byControlId[row.controlId] = row end
        if row.settingKey ~= "" then
            local existing = built.bySettingKey[row.settingKey]
            if not existing then
                built.bySettingKey[row.settingKey] = row
            elseif type(existing[1]) == "table" then
                existing[#existing + 1] = row
            else
                built.bySettingKey[row.settingKey] = { existing, row }
            end
        end
    end
    index = built
    return built
end

function Schema.GetBySemanticId(semanticId)
    return CopyRecord(EnsureIndex().bySemanticId[Trim(semanticId)])
end

function Schema.GetBySettingKey(settingKey)
    local entry, out = EnsureIndex().bySettingKey[Trim(settingKey)], {}
    if not entry then return out end
    local rows = type(entry[1]) == "table" and entry or { entry }
    for i = 1, #rows do if Available(rows[i]) then out[#out + 1] = CopyRecord(rows[i]) end end
    return out
end

function Schema.CanonicalQuery(descriptor)
    return CanonicalSearchText(type(descriptor) == "table" and descriptor or {})
end

-- Exact canonical lookup is deliberately unbounded. If reviewed metadata ever
-- collides, callers receive every match plus an explicit "ambiguous" status;
-- no top-N truncation is allowed to turn that collision into a mutation.
function Schema.FindCanonical(label, opts)
    opts = type(opts) == "table" and opts or {}
    if type(label) == "table" then
        local descriptor = label
        label = descriptor.label
        if opts.pageKey == nil then opts.pageKey = descriptor.pageKey end
        if opts.controlPath == nil then opts.controlPath = descriptor.controlPath end
    end
    local wantedLabel = Normalize(label)
    local wantedPage = Normalize(opts.pageKey)
    local wantedPath = Normalize(opts.controlPath)
    if wantedLabel == "" or wantedPage == "" or wantedPath == "" then return {}, "needs_scope" end

    local contextId, stateId = opts.contextId or CurrentContextId(), opts.stateId
    local out, built = {}, EnsureIndex()
    for i, row in ipairs(built.rows) do
        if Available(row, contextId) and StateAvailable(row, stateId)
            and Normalize(row.label) == wantedLabel
            and Normalize(row.pageKey) == wantedPage
            and Normalize(row.controlPath) == wantedPath
        then
            out[#out + 1] = CopyRecord(row)
        end
    end
    table.sort(out, function(left, right) return tostring(left.semanticId) < tostring(right.semanticId) end)
    local status = #out == 1 and "unique" or (#out == 0 and "not_found" or "ambiguous")
    for i = 1, #out do
        out[i]._canonicalStatus = status
        out[i]._collisionCount = #out
    end
    return out, status
end

local function RememberSearch(key, value)
    searchCache[key] = value
    searchOrder[#searchOrder + 1] = key
    if #searchOrder > SEARCH_CACHE_LIMIT then searchCache[table.remove(searchOrder, 1)] = nil end
end

function Schema.Find(query, opts)
    opts = type(opts) == "table" and opts or {}
    local normalized = Normalize(query)
    local tokens, exactTokens = SearchTokenPairs(query)
    if #tokens == 0 then return {} end
    local contextId, stateId = opts.contextId or CurrentContextId(), tostring(opts.stateId or "")
    local limit = math.max(1, math.min(tonumber(opts.limit) or 6, 20))
    -- Identity compares the words as written, never the folded stems, so a
    -- request for "combo points" can never claim to BE "combo point".
    local queryTokenKey = table.concat(exactTokens, "\031")
    local queryIdentityKey = normalized
    local queryIdentityAlternate = CanonicalIdentityQuery(query)
    local queryRawLabel = Trim(query):lower()
    local cacheKey = contextId .. "\031" .. stateId .. "\031" .. tostring(limit) .. "\031" .. normalized
    if searchCache[cacheKey] then
        local copy = {}
        for i = 1, #searchCache[cacheKey] do
            local cached = searchCache[cacheKey][i]
            copy[i] = CopyRecord(cached.row)
            copy[i]._score = cached.score
            copy[i].matchedValue = cached.matchedValue
        end
        return copy
    end
    -- Family words are scored but not demanded, so "unitframe border" keeps the
    -- unit pages' Border controls instead of collapsing to zero hits.
    local requiredCount, scopePrefixes = 0, nil
    for t = 1, #tokens do
        local prefix = SCOPE_TOKENS[tokens[t]]
        if prefix then
            scopePrefixes = scopePrefixes or {}
            scopePrefixes[prefix] = true
        else
            requiredCount = requiredCount + 1
        end
    end
    if requiredCount == 0 then requiredCount = #tokens; scopePrefixes = nil end
    local wantsSection = normalized:find("section", 1, true) or normalized:find("expand", 1, true)
        or normalized:find("collapse", 1, true) or normalized:find("accordion", 1, true)
    local queryTokenSet = {}
    for t = 1, #tokens do queryTokenSet[tokens[t]] = true end
    -- Naming a frame rules the other frames out. Offering Target of Target's
    -- control to someone who wrote "target" is not a near miss; it is a
    -- different frame. Pages that are not unit frames stay eligible either way.
    local allowedUnitPages = NamedUnitPages(" " .. normalized .. " ")

    local candidates, built = {}, EnsureIndex()
    for i, row in ipairs(built.rows) do
        local wrongUnitPage = allowedUnitPages and SCOPE_PAGES[tostring(row.pageKey or "")]
            and not allowedUnitPages[tostring(row.pageKey or "")]
        -- A scope word can also be part of the control's complete label. For
        -- example, "Current target only" exists on every Unit Frame page and
        -- must remain ambiguous without a separately named frame. Preserve
        -- exact duplicate labels here; explicit scoped requests still filter.
        if wrongUnitPage and tostring(row.label or ""):lower() == queryRawLabel then
            wrongUnitPage = false
        end
        if not wrongUnitPage and Available(row, contextId) and StateAvailable(row, stateId) then
            local score, matched, labelHits = 0, 0, 0
            for t = 1, #tokens do
                local token = tokens[t]
                local isScope = SCOPE_TOKENS[token] ~= nil
                local start = built.search[i]:find(token, 1, true)
                if start then
                    if not isScope then matched = matched + 1 end
                    score = score + (start == 1 and 9 or 4)
                    -- The stem got us here; spelling it exactly as the player
                    -- did is stronger evidence. Without this, "borders" scores
                    -- the same on "Border" and "Borders" and the tie is settled
                    -- alphabetically rather than by what was asked for.
                    local exact = exactTokens[t]
                    if exact ~= token and built.search[i]:find(exact, 1, true) then score = score + 5 end
                    if LazyLower(built.labelSearch, i, row.label):find(token, 1, true) then
                        score = score + 6
                        if not isScope then labelHits = labelHits + 1 end
                    end
                    if LazyLower(built.pageSearch, i, row.pageKey):find(token, 1, true) then score = score + 6 end
                    if LazyLower(built.valueSearch, i, row.values):find(token, 1, true) then score = score + 8 end
                end
            end
            if matched == requiredCount then
                -- A control whose own name carries the whole request beats one
                -- that merely mentions the words in its help text or path:
                -- "icon border style" is Border Style, not the Icon Border
                -- section header that happens to sit on an icon-style path.
                if labelHits > 0 and labelHits == requiredCount then score = score + 14 end
                -- The other direction of the same idea: every word of the
                -- control's own name was written by the player. "aura border
                -- thickness" names Border Thickness completely, while Border /
                -- Glow Thickness keeps a word ("glow") nobody asked for.
                local labelTokens = built.labelTokens[i]
                if labelTokens == nil then
                    labelTokens = SearchTokens(row.label)
                    built.labelTokens[i] = labelTokens
                end
                if #labelTokens > 0 then
                    local covered = true
                    for lt = 1, #labelTokens do
                        if not queryTokenSet[labelTokens[lt]] then covered = false; break end
                    end
                    if covered then score = score + (#labelTokens >= 2 and 16 or 8) end
                end
                if scopePrefixes then
                    local pageKey = tostring(row.pageKey or "")
                    for prefix in pairs(scopePrefixes) do
                        if pageKey:sub(1, #prefix) == prefix then score = score + 12; break end
                    end
                end
                -- Accordion open/close toggles share every word with the
                -- controls they contain. Nobody setting a value means the
                -- section header, so it only competes when asked for by name.
                if not wantsSection and tostring(row.controlPath or ""):find("/section/", 1, true)
                    and tostring(row.controlPath or ""):sub(-9) == "/expanded"
                then score = score - 20 end
                local bestValue, bestValueMatches = nil, 0
                for _, valueRow in ipairs(DecodeValues(row.values)) do
                    local valueSearch, valueMatches = Normalize(tostring(valueRow.value) .. " " .. tostring(valueRow.text)), 0
                    for t = 1, #tokens do
                        if not SCOPE_TOKENS[tokens[t]] and valueSearch:find(tokens[t], 1, true) then
                            valueMatches = valueMatches + 1
                        end
                    end
                    if valueMatches > bestValueMatches then bestValueMatches, bestValue = valueMatches, valueRow.text end
                end
                if bestValueMatches == requiredCount then score = score + 12 end
                local asksAuraLane = normalized:find("buff", 1, true) or normalized:find("debuff", 1, true)
                if asksAuraLane then
                    local controlPath = Normalize(row.controlPath)
                    if controlPath:find("aura", 1, true) then score = score + 10 end
                    if controlPath:find("anchor", 1, true) then score = score - 15 end
                    if normalized:find("target", 1, true)
                        and (row.pageKey == "uf_target" or tostring(row.settingKey):find(".target.", 1, true))
                    then score = score + 8 end
                end
                -- A label-only request with duplicate exact labels must remain
                -- a tie. Page/value coincidences are not permission to choose
                -- one control silently. Adding canonical page/path identity,
                -- however, receives a deterministic exact-match bonus.
                local labelTokenKey = built.labelTokenKey[i]
                if labelTokenKey == nil then
                    labelTokenKey = ExactTokenKey(row.label)
                    built.labelTokenKey[i] = labelTokenKey
                end
                if queryTokenKey == labelTokenKey then score = 200 end
                local canonicalIdentityKey = built.canonicalIdentityKey[i]
                if canonicalIdentityKey == nil then
                    canonicalIdentityKey = Normalize(CanonicalSearchText(row))
                    built.canonicalIdentityKey[i] = canonicalIdentityKey
                end
                if queryIdentityKey == canonicalIdentityKey or queryIdentityAlternate == canonicalIdentityKey then
                    score = score + 1000
                end
                local inserted = false
                for at = 1, #candidates do
                    if score > candidates[at].score or (score == candidates[at].score and row.semanticId < candidates[at].row.semanticId) then
                        table.insert(candidates, at, { row = row, score = score, matchedValue = bestValue }); inserted = true; break
                    end
                end
                if not inserted then candidates[#candidates + 1] = { row = row, score = score, matchedValue = bestValue } end
                if #candidates > limit then table.remove(candidates) end
            end
        end
    end
    local raw, out = {}, {}
    for i = 1, #candidates do
        local candidate, bestValue = candidates[i], candidates[i].matchedValue
        raw[i] = candidate
        out[i] = CopyRecord(candidates[i].row)
        out[i]._score = candidates[i].score
        out[i].matchedValue = bestValue
    end
    RememberSearch(cacheKey, raw)
    return out
end

function Schema.Resolve(semanticId, opts)
    opts = type(opts) == "table" and opts or {}
    local descriptor = Schema.GetBySemanticId(semanticId)
    if not descriptor then return false, "unknown_control" end
    if not descriptor.available then return false, "context_unavailable", descriptor end
    if opts.open == true then
        if descriptor.settingKey ~= "" and type(M.OpenExactSettingControl) == "function" then
            local ok, message = M.OpenExactSettingControl(descriptor.settingKey, descriptor.label, descriptor.pageKey)
            return ok ~= false, message, descriptor
        end
        if type(M.OpenExactCatalogControl) == "function" then
            local ok, message = M.OpenExactCatalogControl(descriptor.semanticId, descriptor.label, descriptor.pageKey)
            return ok ~= false, message, descriptor
        end
        if type(M.Open) == "function" and descriptor.pageKey ~= "" then
            local ok = M.Open(descriptor.pageKey)
            if ok == false then return false, "open_failed", descriptor end
            return true, "Opened " .. tostring(descriptor.label or descriptor.pageKey) .. ".", descriptor
        end
    end
    local catalog = M.RuntimeControlCatalog
    if catalog and type(catalog.Resolve) == "function" then
        local live, widget = catalog.Resolve(semanticId, { pageKey = descriptor.pageKey, memberKey = descriptor.memberKey })
        if live then return true, live, widget, descriptor end
    end
    return true, descriptor
end

function Schema.Read(semanticId)
    local descriptor = Schema.GetBySemanticId(semanticId)
    if not descriptor or not descriptor.available then return false, "context_unavailable" end
    local Registry = A.Registry
    local setting = descriptor.settingKey ~= "" and Registry and Registry.GetSetting and Registry:GetSetting(descriptor.settingKey) or nil
    if setting and type(setting.get) == "function" then
        local ok, value = pcall(setting.get)
        if ok then return true, value, descriptor end
        return false, "read_failed", descriptor
    end
    local catalog = M.RuntimeControlCatalog
    if catalog and catalog.Read then return catalog.Read(descriptor.controlId) end
    return false, "read_unavailable", descriptor
end

local function FiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function ClampNumber(value, minimum, maximum, step)
    minimum, maximum, step = tonumber(minimum), tonumber(maximum), tonumber(step)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    if step and step > 0 then
        local base = minimum or 0
        value = base + math.floor(((value - base) / step) + 0.5) * step
        if minimum and value < minimum then value = minimum end
        if maximum and value > maximum then value = maximum end
    end
    return value
end

local function ExactChoice(setting, input)
    local Parser = A.Parser
    if type(A.RefreshAssistantSettingValues) == "function" then
        A.RefreshAssistantSettingValues(setting)
    elseif Parser and type(Parser.RefreshRegistrySettingValues) == "function" then
        Parser.RefreshRegistrySettingValues(setting)
    end
    local inputText = type(input) == "string" and Normalize(input) or nil
    local values = type(setting.values) == "table" and setting.values or {}
    local labels = type(setting.valueLabels) == "table" and setting.valueLabels or {}
    for i = 1, #values do
        local candidate = values[i]
        if input == candidate then return true, candidate end
        if inputText and (inputText == Normalize(candidate) or inputText == Normalize(labels[candidate])) then
            return true, candidate
        end
    end
    return false
end

-- Direct schema callers do not pass through the natural-language parser. Keep
-- the same Registry contract here so malformed values cannot rely on Lua
-- truthiness or individual setter clamping.
function Schema.NormalizeSettingValue(setting, value)
    if type(setting) ~= "table" then return false, "missing_setting" end
    local settingType = tostring(setting.type or "")
    if settingType == "boolean" then
        if type(value) ~= "boolean" then return false, "expected_boolean" end
        if type(A.NormalizeRegistrySettingValue) == "function" then
            local ok, normalized = A.NormalizeRegistrySettingValue(setting, value)
            if not ok then return false, "expected_boolean" end
            return true, normalized
        end
        return true, value
    end
    if settingType == "number" then
        if not FiniteNumber(value) then return false, "expected_number" end
        if type(A.NormalizeRegistrySettingValue) == "function" then
            local ok, normalized = A.NormalizeRegistrySettingValue(setting, value)
            return ok and true or false, ok and normalized or "expected_number"
        end
        return true, ClampNumber(value, setting.min, setting.max, setting.step)
    end
    if settingType == "enum" then
        local matched, canonical = ExactChoice(setting, value)
        if not matched then return false, "expected_choice" end
        if type(A.NormalizeRegistrySettingValue) == "function" then
            local ok, normalized = A.NormalizeRegistrySettingValue(setting, canonical, { skipRefresh = true })
            return ok and true or false, ok and normalized or "expected_choice"
        end
        return true, canonical
    end
    if settingType == "string" then
        if type(value) ~= "string" then return false, "expected_text" end
        if type(setting.values) == "table" and #setting.values > 0 and setting.closedValues == true then
            local matched, canonical = ExactChoice(setting, value)
            if not matched then return false, "expected_choice" end
            if type(A.NormalizeRegistrySettingValue) == "function" then
                local ok, normalized = A.NormalizeRegistrySettingValue(setting, canonical, { skipRefresh = true })
                return ok and true or false, ok and normalized or "expected_choice"
            end
            return true, canonical
        end
        if type(A.NormalizeRegistrySettingValue) == "function" then
            local ok, normalized = A.NormalizeRegistrySettingValue(setting, value)
            return ok and true or false, ok and normalized or "expected_text"
        end
        return true, value
    end
    if settingType == "color" then
        if type(value) ~= "table" then return false, "expected_color" end
        local r = value.r ~= nil and value.r or value[1]
        local g = value.g ~= nil and value.g or value[2]
        local b = value.b ~= nil and value.b or value[3]
        local a = value.a ~= nil and value.a or value[4]
        if a == nil then a = 1 end
        if not FiniteNumber(r) or not FiniteNumber(g) or not FiniteNumber(b) or not FiniteNumber(a)
            or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 or a < 0 or a > 1
        then return false, "expected_color" end
        local normalized = { r = r, g = g, b = b, a = a, r, g, b, a }
        if type(A.NormalizeRegistrySettingValue) == "function" then
            local ok, shared = A.NormalizeRegistrySettingValue(setting, normalized)
            return ok and true or false, ok and shared or "expected_color"
        end
        return true, normalized
    end
    return false, "unsupported_setting_type"
end

local PLAN_ACCEPTED = {
    applied = true,
    unchanged = true,
    queued = true,
    confirmation_needed = true,
    confirm = true,
}

local function ExecuteThroughPlan(plan, opts)
    local result = A.ExecutePlan(plan, opts)
    if type(result) == "table" then
        local status = tostring(result.status or result.result or "")
        if plan and plan.kind == "action" and result._readOnlyGuard ~= true
            and (status == "navigated" or status == "info")
        then
            return true, result
        end
        return PLAN_ACCEPTED[status] == true, result
    end
    return result ~= false and result ~= nil, result
end

local function EmptyArgs(args)
    return args == nil or (type(args) == "table" and next(args) == nil)
end

function Schema.ResolveActionFixedValue(value, seen, depth)
    local valueType = type(value)
    if value == nil or valueType == "boolean" or valueType == "string" then return value end
    if valueType == "number" then
        if not FiniteNumber(value) then return nil, "nonfinite_fixed_action_value" end
        return value
    end
    if valueType ~= "table" or getmetatable(value) ~= nil then return nil, "invalid_fixed_action_value" end
    depth = (tonumber(depth) or 0) + 1
    if depth > 12 then return nil, "fixed_action_value_too_deep" end
    seen = seen or {}
    if seen[value] then return nil, "cyclic_fixed_action_value" end
    seen[value] = true
    if value.context ~= nil then
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        if count ~= 1 or type(value.context) ~= "string" then
            seen[value] = nil
            return nil, "invalid_action_context_marker"
        end
        if value.context == "activeProfile" then
            local active = rawget(_G, "MSUF_ActiveProfile")
            seen[value] = nil
            if type(active) ~= "string" or Trim(active) == "" then return nil, "active_profile_unavailable" end
            return active
        end
        seen[value] = nil
        return nil, "unknown_action_context_marker"
    end
    local out = {}
    for key, child in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then
            seen[value] = nil
            return nil, "invalid_fixed_action_key"
        end
        local resolved, err = Schema.ResolveActionFixedValue(child, seen, depth)
        if err then seen[value] = nil; return nil, err end
        out[key] = resolved
    end
    seen[value] = nil
    return out
end

function Schema.BuildActionArgs(descriptor, value, opts, parsedAction)
    opts = type(opts) == "table" and opts or {}
    local args = {}
    if descriptor.actionFixedArgs ~= nil then
        local fixed, fixedError = Schema.ResolveActionFixedValue(descriptor.actionFixedArgs)
        if type(fixed) ~= "table" then return nil, fixedError or "invalid_fixed_action_args" end
        for key, item in pairs(fixed) do args[key] = item end
    end
    if parsedAction then
        if opts.args ~= nil and (type(opts.args) ~= "table" or getmetatable(opts.args) ~= nil) then
            return nil, "invalid_parsed_action_args"
        end
        for key, item in pairs(opts.args or {}) do
            if args[key] ~= nil then return nil, "fixed_action_arg_conflict" end
            args[key] = item
        end
        return args
    end
    if not EmptyArgs(opts.args) then return nil, "immutable_action_args" end
    local inputArg = Trim(descriptor.actionInputArg)
    if inputArg ~= "" then
        if value == nil then return nil, "missing_action_input" end
        if args[inputArg] ~= nil then return nil, "fixed_action_arg_conflict" end
        args[inputArg] = value
    elseif value ~= nil then
        return nil, "unexpected_action_input"
    end
    return args
end

function Schema.BuildCatalogBackedSetting(descriptor, opts)
    if type(descriptor) ~= "table" or descriptor.classification ~= "setting"
        or Trim(descriptor.settingKey) ~= ""
    then return nil, "not_catalog_backed" end
    local settingType = descriptor.valueKind == "boolean" and "boolean"
        or descriptor.valueKind == "number" and "number"
        or descriptor.valueKind == "enum" and "enum"
        or descriptor.valueKind == "string" and "string"
        or descriptor.valueKind == "color" and "color" or nil
    if not settingType then return nil, "reviewed_owner_required" end
    local catalog = M.RuntimeControlCatalog
    if not (catalog and type(catalog.Resolve) == "function" and type(catalog.Read) == "function") then
        return nil, "catalog_unavailable"
    end
    local live = select(1, catalog.Resolve(descriptor.semanticId, { pageKey = descriptor.pageKey }))
    if not live and (type(opts) ~= "table" or opts.open ~= false) then
        Schema.Resolve(descriptor.semanticId, { open = true })
        live = select(1, catalog.Resolve(descriptor.semanticId, { pageKey = descriptor.pageKey }))
    end
    if type(live) ~= "table" then return nil, "stale_control" end
    local disposition = tostring(live.assistantDisposition or "")
    if disposition ~= "dynamic" and disposition ~= "compound" and disposition ~= "duplicate" then
        return nil, "unreviewed_catalog_setting"
    end
    local command = live.command
    if type(command) ~= "table" or type(command.get) ~= "function" or type(command.set) ~= "function" then
        return nil, "catalog_setting_unavailable"
    end
    local settingKey = "catalog." .. tostring(descriptor.semanticId)
    local Registry = A.Registry
    local setting = Registry and type(Registry.GetSetting) == "function" and Registry:GetSetting(settingKey) or nil
    if setting and setting.catalogTransactionBacked ~= true then return nil, "catalog_setting_key_collision" end
    setting = setting or {
        key = settingKey,
        label = descriptor.label, type = settingType,
        combatSafe = false, assistantMutationSafe = true,
        catalogTransactionBacked = true,
    }
    setting.label, setting.type = descriptor.label, settingType
    setting.min, setting.max, setting.step = tonumber(descriptor.min), tonumber(descriptor.max), tonumber(descriptor.step)
    setting.values, setting.valueLabels, setting.closedValues = {}, {}, settingType == "enum"
    for i = 1, #(descriptor.values or {}) do
        local row = descriptor.values[i]
        setting.values[#setting.values + 1] = row.value
        setting.valueLabels[row.value] = row.text
    end
    if #setting.values == 0 then setting.values, setting.valueLabels = nil, nil end
    setting.percent = settingType == "number" and descriptor.percentIsValue ~= true
        and descriptor.percentIsValue ~= "1" and setting.max ~= nil and setting.max <= 1
    setting._catalogBinding = { live = live, command = command, catalog = catalog, settingType = settingType }
    setting.get = function()
        local binding = setting._catalogBinding
        local ok, first, second, third, fourth = binding.catalog.Read(binding.live.controlId)
        if ok ~= true then error(tostring(first or "catalog read failed")) end
        if binding.settingType == "color" then
            if type(first) == "table" then return first end
            return { r = first, g = second, b = third, a = fourth == nil and 1 or fourth }
        end
        return first
    end
    setting.set = function(nextValue)
        local binding = setting._catalogBinding
        local activeCommand = binding.command
        if type(activeCommand.blockCombat) == "function" then
            local ok, blocked = pcall(activeCommand.blockCombat)
            if not ok or blocked == true then error("catalog setting is blocked") end
        end
        if type(activeCommand.canExecute) == "function" then
            local ok, executable = pcall(activeCommand.canExecute)
            if not ok or executable ~= true then error("catalog setting is unavailable") end
        end
        local ok, result
        if binding.settingType == "color" then
            ok, result = pcall(activeCommand.set, nextValue.r, nextValue.g, nextValue.b, nextValue.a)
        else
            ok, result = pcall(activeCommand.set, nextValue)
        end
        if not ok then error(result) end
        if result == false then error("catalog setting rejected the value") end
        if type(activeCommand.refresh) == "function" then pcall(activeCommand.refresh) end
        return nextValue
    end
    if type(A.CaptureSnapshot) ~= "function" or type(A.RestoreSnapshot) ~= "function" then
        return nil, "catalog_snapshot_unavailable"
    end
    setting.captureTransactionState = A.CaptureSnapshot
    setting.restoreTransactionState = function(state, reason)
        local restored = A.RestoreSnapshot(state, reason)
        local binding = setting._catalogBinding
        if restored and binding and type(binding.command.refresh) == "function" then pcall(binding.command.refresh) end
        return restored
    end
    if Registry and type(Registry.RegisterSetting) == "function" then
        setting = Registry:RegisterSetting(setting) or setting
    end
    return setting
end

-- Unforgeable within the addon API: only TryConversation can attach this after
-- the matched Registry action itself has parsed and validated the raw request.
-- Public Schema.Execute callers remain unable to redirect a semantic control
-- with arbitrary action arguments.
local PARSED_ACTION_CAPABILITY = {}

function Schema.Execute(semanticId, value, opts)
    opts = type(opts) == "table" and opts or {}
    local descriptor = Schema.GetBySemanticId(semanticId)
    if not descriptor or not descriptor.available then return false, "context_unavailable" end
    local reviewedCatalogSetting = descriptor.classification == "setting" and descriptor.settingKey == ""
        and (descriptor.valueKind == "boolean" or descriptor.valueKind == "number"
            or descriptor.valueKind == "enum" or descriptor.valueKind == "string" or descriptor.valueKind == "color")
    if descriptor.safety == "guided" and not reviewedCatalogSetting then return false, descriptor.safety end
    if descriptor.safety == "readOnly" and descriptor.actionKey == "" then return false, descriptor.safety end
    local Registry = A.Registry
    local setting = descriptor.settingKey ~= "" and Registry and Registry.GetSetting and Registry:GetSetting(descriptor.settingKey) or nil
    if not setting and reviewedCatalogSetting then
        local catalogError
        setting, catalogError = Schema.BuildCatalogBackedSetting(descriptor, opts)
        if not setting then return false, catalogError or "guided", descriptor end
    end
    if setting and type(A.ExecutePlan) == "function" then
        if opts.inputUnit ~= nil and opts.inputUnit ~= "native" and opts.inputUnit ~= "percent" then
            return false, "invalid_input_unit", descriptor
        end
        if opts.inputUnit == "percent" then
            if setting.percent ~= true or type(value) ~= "number" then
                return false, "invalid_input_unit", descriptor
            end
            value = value / 100
        end
        local valid, normalized = Schema.NormalizeSettingValue(setting, value)
        if not valid then return false, "invalid_value", descriptor, normalized end
        return ExecuteThroughPlan({ kind = "changes", changes = { { setting = setting, value = normalized } },
            confirmRequired = opts.confirmRequired == true or descriptor.safety == "confirm"
                or descriptor.confirmRequired == true or descriptor.confirmRequired == "1",
            label = opts.label or descriptor.label or setting.label or descriptor.settingKey,
            summary = opts.summary or ("Change " .. tostring(descriptor.label or setting.label or descriptor.settingKey)) },
            { confirmed = opts.confirmed == true, sourceText = opts.sourceText })
    end
    local action = descriptor.actionKey ~= "" and Registry and Registry.GetAction and Registry:GetAction(descriptor.actionKey) or nil
    if action and type(A.ExecutePlan) == "function" then
        local parsedAction = opts._parsedActionCapability == PARSED_ACTION_CAPABILITY
        local args, argsError = Schema.BuildActionArgs(descriptor, value, opts, parsedAction)
        if not args then return false, argsError or "invalid_action_input", descriptor end
        if action.assistantInputExplicit ~= true or type(A.NormalizeAssistantActionInput) ~= "function" then
            return false, "missing_action_contract", descriptor
        end
        local normalized, normalizeError = A.NormalizeAssistantActionInput(action, args)
        if not normalized then return false, "invalid_action_input", descriptor, normalizeError end
        return ExecuteThroughPlan({ kind = "action", action = action, args = normalized,
            confirmRequired = opts.confirmRequired == true or descriptor.safety == "confirm"
                or descriptor.confirmRequired == true or descriptor.confirmRequired == "1",
            label = opts.label or descriptor.label or action.label,
            summary = opts.summary or descriptor.label or action.label },
            { confirmed = opts.confirmed == true, sourceText = opts.sourceText })
    end
    local catalog = M.RuntimeControlCatalog
    if not (catalog and catalog.Execute) then return false, "stale_control", descriptor end
    -- Persisted controls must have resolved through Registry + ExecutePlan
    -- above. Raw Menu2 callbacks do not participate in Assistant snapshots or
    -- undo/redo, so catalog execution is reserved for transient preview/test
    -- state only.
    if descriptor.classification ~= "ephemeral" or descriptor.safety ~= "nonStateful" then
        return false, "guided", descriptor
    end
    if descriptor.safety == "confirm" and opts.confirmed ~= true then return false, "confirmation_required", descriptor end
    local live = catalog.Resolve and select(1, catalog.Resolve(semanticId, { pageKey = descriptor.pageKey })) or nil
    if not live and opts.open ~= false and type(M.Open) == "function" and descriptor.pageKey ~= "" then
        M.Open(descriptor.pageKey)
        live = catalog.Resolve and select(1, catalog.Resolve(semanticId, { pageKey = descriptor.pageKey })) or nil
    end
    if not live then return false, "stale_control", descriptor end
    return catalog.Execute(live.controlId, value, opts)
end

-- A few catalogued dropdowns carry their CURRENT VALUE as their name, because
-- that is the text the closed widget shows. The Focus Target portrait border
-- style is catalogued as "No border", which turns an answer into "No border is
-- at Frames > Unitframes > Focus Target > No border".
--
-- Search is unaffected -- the indexed text includes the setting key, so
-- "portrait border style" still finds it -- so this repairs the name only where
-- it is shown, and only when the name really is one of the control's own
-- choices. The camelCase setting key is the reliable source for the real name.
local function DisplayLabel(descriptor)
    local label = tostring(descriptor and descriptor.label or "")
    local settingKey = tostring(descriptor and descriptor.settingKey or "")
    if label == "" or settingKey == "" then return label end
    local values = descriptor.values
    if type(values) ~= "table" or #values == 0 then return label end
    local normalizedLabel, looksLikeValue = Normalize(label), false
    for i = 1, #values do
        if Normalize(values[i].text) == normalizedLabel then looksLikeValue = true; break end
    end
    if not looksLikeValue then return label end
    local attribute = settingKey:match("[%./]([%w_]+)$") or settingKey
    attribute = attribute:gsub("(%l)(%u)", "%1 %2"):gsub("_", " ")
    if attribute == "" then return label end
    return attribute:sub(1, 1):upper() .. attribute:sub(2):lower()
end

-- The first control-path segment that differs between two look-alike rows, as
-- a short human hint ("overlay" vs "symbol").
local function DistinguishingSegment(row, other)
    local mine, theirs = {}, {}
    for segment in tostring(row and row.controlPath or ""):gmatch("[^/]+") do mine[#mine + 1] = segment end
    for segment in tostring(other and other.controlPath or ""):gmatch("[^/]+") do theirs[#theirs + 1] = segment end
    for i = 1, #mine do
        if mine[i] ~= theirs[i] then return (mine[i]:gsub("[-_]", " ")) end
    end
    return ""
end

local function PageBreadcrumb(descriptor)
    local pageKey = tostring(descriptor and descriptor.pageKey or "")
    local page = type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(pageKey)
        or pageKey:gsub("_", " ")
    if page == "" then page = "MSUF options" end
    return tostring(page)
end

local function HumanPath(descriptor)
    local page = PageBreadcrumb(descriptor)
    local label = DisplayLabel(descriptor)
    if label == "" or page:find(label, 1, true) then return page end
    return page .. " > " .. label
end

local function BooleanIntent(normalized)
    if normalized:find(" disable ", 1, true) or normalized:match("^disable ") or normalized:find(" turn off ", 1, true)
        or normalized:find(" ausschalten ", 1, true) or normalized:find(" deaktivieren ", 1, true)
    then return false end
    if normalized:find(" enable ", 1, true) or normalized:match("^enable ") or normalized:find(" turn on ", 1, true)
        or normalized:find(" einschalten ", 1, true) or normalized:find(" aktivieren ", 1, true)
    then return true end
end

local MUTATION_TERMS = {
    "set", "change", "make", "turn", "enable", "disable", "toggle", "switch", "use", "apply", "adjust",
    "choose", "select", "pick", "hide", "edit", "configure", "update", "move", "reorder", "reset", "clear",
    "delete", "add", "remove", "create", "rename", "copy", "import", "export", "run", "start", "stop",
    -- Players describe the outcome, not the widget: "style the aura border",
    -- "thicken the outline", "shrink the pet frame". Without these the request
    -- never reaches control resolution at all and falls out as unsupported.
    -- Colour verbs are deliberately absent: the router owns dedicated colour
    -- lanes that answer far better than a generic control match would.
    "style", "restyle", "customize", "customise", "custom", "tweak", "modify",
    "increase", "decrease", "raise", "lower", "grow", "shrink", "resize", "rescale",
    "thicken", "thin", "widen", "narrow", "expand", "collapse",
    "put", "give", "keep", "replace", "swap", "assign", "bump", "reduce", "boost",
    "setze", "stelle", "aendere", "aktiviere", "deaktiviere", "waehle", "nutze", "verwende", "umschalten",
    "verschiebe", "sortiere", "loesche", "erstelle", "kopiere", "importiere", "exportiere", "starte", "stoppe",
}

local MUTATION_WRAPPERS = {
    "please ", "can you ", "could you ", "would you ", "will you ", "can you please ",
    "could you please ", "would you please ", "i want to ", "i want you to ", "help me ",
    -- Question-shaped requests are still requests. Each of these only strips a
    -- prefix; the remainder must still begin with a real mutation verb, so
    -- "how do i find the aura page" stays a lookup rather than a change.
    "how do i ", "how do you ", "how can i ", "how would i ", "how to ",
    "is it possible to ", "would it be possible to ", "is there a way to ",
    "i would like to ", "id like to ", "i need to ", "i need you to ",
    "i want ", "can i ", "could i ", "let me ", "lets ", "let us ",
    "bitte ", "kannst du ", "koenntest du ", "ich moechte ",
}

local function StripMutationWrappers(normalized)
    local actionable, changed = Trim(normalized), true
    while changed do
        changed = false
        for i = 1, #MUTATION_WRAPPERS do
            local wrapper = MUTATION_WRAPPERS[i]
            if actionable:sub(1, #wrapper) == wrapper then
                actionable = Trim(actionable:sub(#wrapper + 1))
                changed = true
                break
            end
        end
    end
    return actionable
end

local function LeadingMutationTerm(actionable)
    for i = 1, #MUTATION_TERMS do
        local term = MUTATION_TERMS[i]
        if actionable == term or actionable:sub(1, #term + 1) == term .. " " then return term end
    end
end

local function HasMutationIntent(normalized)
    if normalized:find(" show me ", 1, true) or normalized:find(" show me where ", 1, true) then return false end
    return LeadingMutationTerm(StripMutationWrappers(normalized)) ~= nil
end

local function MutationTargetText(text)
    local raw = tostring(text or "")
    local rawWithoutQuoted = raw:gsub('%s+"[^"]*"%s*$', ""):gsub("%s+'[^']*'%s*$", "")
    local normalized = Normalize(raw)
    local target = normalized:match("^(.-)%s+to%s+.+$")
        or normalized:match("^(.-)%s+as%s+.+$")
        or normalized:match("^(.-)%s+is%s+.+$")
        or normalized:match("^(.-)%s+be%s+.+$")
        or normalized:match("^(.-)%s+value%s+.+$")
        or normalized:match("^(.-)%s+auf%s+.+$")
        or normalized:match("^(.-)%s+zu%s+.+$")
        or normalized:match("^(.-)%s+als%s+.+$")
        or normalized:match("^(.-)%s+wert%s+.+$")
    if not target then
        local equals = raw:match("^(.-)%s*=%s*.+$")
        if equals and Trim(equals) ~= "" then target = equals end
    end
    if not target then
        if rawWithoutQuoted ~= raw and Trim(rawWithoutQuoted) ~= "" then
            target = rawWithoutQuoted
        else
            -- A quoted/free-form value or literal color is not part of the
            -- control identity. Remove only a trailing value-shaped segment;
            -- enum values stay in the full query so they can improve choice
            -- matching.
            target = normalized:gsub("%s+#[0-9a-f]+$", ""):gsub("%s+rgba?%s*%b()$", "")
        end
    end
    if Trim(target) == "" then return text, nil end
    -- Politeness in front of the verb is never control identity.
    local actionable = StripMutationWrappers(Normalize(target))
    -- The verb itself is ambiguous evidence. "style" is grammar in "style the
    -- aura border" but part of the name in "icon border style", so the caller
    -- gets both readings: the full phrase first, and this verb-less retry only
    -- if the full phrase matches nothing. Without the retry, "customize the
    -- aura border thickness" needs a control literally named "customize" and
    -- finds none.
    local leading = LeadingMutationTerm(actionable)
    local withoutVerb
    if leading then
        withoutVerb = Trim(actionable:sub(#leading + 1))
        if withoutVerb == "" then withoutVerb = nil end
    end
    if actionable == "" then return target, withoutVerb end
    return actionable, withoutVerb
end

-- Only grammar words. Search drops verbs like "show" and "hide" because they
-- are how requests are phrased, but inside a control's NAME they carry the
-- meaning -- "Show on Target castbar" is not "the target castbar". This check
-- therefore keeps every word search throws away except pure connectives.
local NAME_GRAMMAR = {
    a = true, an = true, the = true, of = true, on = true, ["in"] = true, ["for"] = true,
    to = true, ["and"] = true, ["or"] = true, at = true, by = true, with = true,
    per = true, its = true,
}

-- Did the player actually name this control, or did search merely land on it?
-- Every meaningful word of the control's own name has to appear in the request.
-- It is the difference between "tweak the player frame width" (Player Width --
-- worth asking which number) and "restyle the target castbar" (Show on Target
-- castbar -- clearly not what was meant).
local function RequestNamesControl(normalized, top)
    local label = Normalize(top and top.label or "")
    if label == "" then return false end
    local sawWord = false
    for word in label:gmatch("%S+") do
        if not NAME_GRAMMAR[word] then
            sawWord = true
            local stem = Singular(word)
            if not normalized:find(word, 1, true) and not normalized:find(stem, 1, true) then
                return false
            end
        end
    end
    return sawWord
end

local function MissingSettingValue(setting, top, text)
    local Parser = A.Parser
    if Parser and type(Parser.MissingValueResponse) == "function" then
        local response = Parser.MissingValueResponse({ { setting = setting, score = top and top._score or 1 } }, text)
        if response and response.kind == "answer" then
            response.result = response.result or response.status or "needs_value"
            response.status = response.status or response.result
            return response
        end
        if response and type(response.choices) == "table" and #response.choices > 0 then
            local labels = {}
            for i = 1, math.min(#response.choices, 12) do
                labels[#labels + 1] = tostring(response.choices[i].valueLabel or response.choices[i].value or response.choices[i].label)
            end
            return {
                text = "What value do you want me to use for " .. tostring(top and top.label or setting and setting.label or "this option")
                    .. "? Choices: " .. table.concat(labels, ", ") .. ".",
                status = "ambiguous", result = "needs_value",
                summary = "Value clarification for an MSUF option.",
            }
        end
    end
    return {
        text = "What value do you want me to use for " .. tostring(top and top.label or setting and setting.label or "this option") .. "?",
        status = "ambiguous", result = "needs_value",
        summary = "Value clarification for an MSUF option.",
    }
end

local function DescriptorValueSetting(top)
    local kind = tostring(top and top.valueKind or "")
    local settingType = kind == "boolean" and "boolean"
        or kind == "number" and "number"
        or kind == "enum" and "enum"
        or (kind == "string" or kind == "text") and "string"
        or kind == "color" and "color" or nil
    if not settingType then return nil end
    local setting = {
        key = tostring(top.semanticId or ""), label = top.label, type = settingType,
        min = tonumber(top.min), max = tonumber(top.max), step = tonumber(top.step),
        values = {}, valueLabels = {}, valueAliases = {}, closedValues = kind == "enum",
    }
    for i = 1, #(top.values or {}) do
        local row = top.values[i]
        setting.values[#setting.values + 1] = row.value
        setting.valueLabels[row.value] = row.text
        local alias = Normalize(row.text)
        if alias ~= "" then setting.valueAliases[alias] = row.value end
    end
    if #setting.values == 0 then setting.values, setting.valueLabels, setting.valueAliases = nil, nil, nil end
    setting.percent = settingType == "number" and not (top.percentIsValue == true or top.percentIsValue == "1")
        and setting.max ~= nil and setting.max <= 1
    return setting
end

local function LastNumber(text)
    local value
    for numberText in tostring(text or ""):gmatch("[%-+]?%d+%.?%d*") do value = tonumber(numberText) end
    return value
end

local function DescriptorInputText(top, text)
    local normalized = Normalize(text)
    local label = Normalize(top and top.label or "")
    local startAt = label ~= "" and normalized:find(label, 1, true) or nil
    if not startAt then return normalized end
    local endAt = startAt + #label - 1
    return normalized:sub(1, startAt - 1) .. " " .. normalized:sub(endAt + 1)
end

local function ParseDescriptorValue(top, text)
    local setting = DescriptorValueSetting(top)
    if not setting then return nil, false end
    local Parser, normalized = A.Parser, Normalize(text)
    -- Relative and proportional wording states no target number: "a bit wider",
    -- "twice as tall", "20% bigger". Every reader below looks for a literal
    -- value, so a catalog-backed control answered these by asking the player for
    -- the number they had just expressed -- and for "20% bigger" the literal
    -- readers would seize the bare 20 and set the value TO 20. Resolve it
    -- against the control's current value first, before any of them run.
    if setting.type == "number" and type(setting.get) == "function"
        and Parser and type(Parser.RelativeNumberDeltaForText) == "function"
    then
        local okDelta, delta = pcall(Parser.RelativeNumberDeltaForText, setting, normalized)
        if okDelta and type(delta) == "number" and delta ~= 0 then
            local okCurrent, current = pcall(setting.get)
            current = okCurrent and tonumber(current) or nil
            if current then
                local valid, canonical = Schema.NormalizeSettingValue(setting, current + delta)
                if valid then return canonical, true end
            end
        end
    end
    if Parser and type(Parser.ValueForRegistrySetting) == "function" then
        local ok, value = pcall(Parser.ValueForRegistrySetting, setting, normalized, text)
        if ok and value ~= nil then
            local valid, canonical = Schema.NormalizeSettingValue(setting, value)
            if valid then return canonical, true end
        end
    end
    local value
    if setting.type == "boolean" then
        value = BooleanIntent(" " .. DescriptorInputText(top, text) .. " ")
    elseif setting.type == "number" then
        value = LastNumber(DescriptorInputText(top, text))
        if value and setting.percent and tostring(text or ""):find("%%") and value > 1 then value = value / 100 end
    elseif setting.type == "enum" and Parser and type(Parser.EnumValueForText) == "function" then
        value = Parser.EnumValueForText(setting, normalized)
        if value == nil and tostring(text or ""):find("%", 1, true) then
            for i = 1, #(setting.values or {}) do
                if setting.values[i] == "PERCENT" then value = "PERCENT" break end
            end
        end
    elseif setting.type == "string" then
        if Parser and type(Parser.StringValueForText) == "function" then
            value = Parser.StringValueForText(setting, normalized, text)
        end
        if value == nil then
            value = tostring(text or ""):match('"([^"]*)"') or tostring(text or ""):match("'([^']*)'")
                or tostring(text or ""):match("[Tt][Oo]%s+(.+)$") or tostring(text or ""):match("=%s*(.+)$")
        end
    elseif setting.type == "color" and Parser and type(Parser.ExtractColor) == "function" then
        local r, g, b, label = Parser.ExtractColor(text, normalized)
        if r ~= nil then value = { r = r, g = g, b = b, label = label } end
    end
    if value == nil then return nil, false end
    local valid, canonical = Schema.NormalizeSettingValue(setting, value)
    return canonical, valid == true
end

-- Schema.Execute's refusals for a catalog-backed control. None of them is a
-- fault: each means the control has to be touched in the menu instead.
local CATALOG_GUIDED_RESULTS = {
    guided = true, not_catalog_backed = true, reviewed_owner_required = true,
    catalog_unavailable = true, unreviewed_catalog_setting = true,
    catalog_setting_unavailable = true, catalog_setting_key_collision = true,
    catalog_snapshot_unavailable = true, stale_control = true,
}

local function MissingDescriptorValue(top)
    local choices = {}
    for i = 1, math.min(#(top.values or {}), 12) do
        choices[#choices + 1] = tostring(top.values[i].text or top.values[i].value)
    end
    local hint = #choices > 0 and (" Choices: " .. table.concat(choices, ", ") .. ".") or ""
    return { text = "What value do you want me to use for " .. tostring(top.label or "that control") .. "?" .. hint,
        status = "ambiguous", result = "needs_value", summary = top.label }
end

local function ExecuteSchemaAction(top, text)
    local Registry = A.Registry
    local action = top and top.actionKey ~= "" and Registry and Registry.GetAction and Registry:GetAction(top.actionKey) or nil
    if not action then return nil end
    local args, meta
    if type(top.actionFixedArgs) == "table" and next(top.actionFixedArgs) ~= nil then
        args, meta = {}, {}
    elseif type(action.parseAliasArgs) == "function" then
        local ok, parsedArgs, parsedMeta = pcall(action.parseAliasArgs, Normalize(text), text, action)
        if not ok or parsedArgs == false then
            return {
                text = "I found " .. tostring(top.label or action.label or "that action")
                    .. ", but I still need its required value or target before I can run it.",
                status = "needs_value", result = "needs_value", summary = top.label or action.label,
            }
        end
        args = type(parsedArgs) == "table" and parsedArgs or {}
        meta = type(parsedMeta) == "table" and parsedMeta or {}
    elseif action.aliasNoArgs == true or (type(action.assistantInput) == "table" and action.assistantInput.kind == "none") then
        args, meta = {}, {}
    else
        return {
            text = "I found " .. tostring(top.label or action.label or "that action")
                .. ", but its arguments are not safe to infer. I kept MSUF unchanged.",
            status = "info", result = "guided", summary = top.label or action.label,
        }
    end
    local ok, result = Schema.Execute(top.semanticId, nil, {
        args = args, sourceText = text,
        _parsedActionCapability = PARSED_ACTION_CAPABILITY,
        confirmRequired = meta.confirmRequired == true,
        label = meta.label, summary = meta.summary,
    })
    if type(result) == "table" then return result end
    if not ok and (result == "readOnly" or result == "guided" or result == "stale_control") then
        return { text = Schema.Render(result == "readOnly" and "readOnly" or "guided", { label = top.label }),
            status = "info", result = result, summary = top.label }
    end
    if not ok then
        return { text = "I found " .. tostring(top.label or action.label) .. ", but it is not available right now.",
            status = "failed", result = tostring(result or "failed"), summary = top.label or action.label }
    end
    return { text = "Done. I ran " .. tostring(top.label or action.label) .. ".",
        status = "applied", result = "applied", summary = top.label or action.label }
end

local function HasAny(normalized, terms)
    for i = 1, #terms do
        local term = terms[i]
        if normalized:find(" " .. term .. " ", 1, true) or normalized:match("^ " .. term .. " ") then return true end
    end
    return false
end

local MODE_MARKERS = { "test", "test mode", "testmode", "preview", "simulate", "simulation", "demo", "vorschau", "testmodus" }
local MODE_LIST_TERMS = { "list", "all", "every", "available", "which", "what", "show all", "liste", "alle", "welche", "verfuegbar" }
local MODE_OFF_TERMS = { "stop", "disable", "off", "hide", "end", "clear", "stoppe", "deaktivieren", "aus", "beenden", "verstecken" }
local MODE_TOGGLE_TERMS = { "toggle", "switch", "umschalten", "wechseln" }
local MODE_START_TERMS = { "start", "run", "launch", "play", "show", "test", "preview", "simulate", "demo", "try", "starte", "starten", "zeige", "vorschau", "testen", "simulieren" }

local function ModeText(row)
    -- Mode identity must come from the control itself. Help text can mention a
    -- neighbouring "Preview" choice (for example the Highlight workspace
    -- selector) without making the selector an executable preview mode.
    return Normalize(table.concat({ row and row.label or "", row and row.controlPath or "", row and row.actionKey or "" }, " "))
end

local function IsLaunchableMode(row)
    if type(row) ~= "table" or row.available == false then return false end
    local kind = tostring(row.kind or "")
    if kind ~= "button" and kind ~= "toggle" and kind ~= "segment" and kind ~= "dropdown" then return false end
    local path = tostring(row.controlPath or ""):lower()
    if path:find("/section/", 1, true) and path:find("/expanded", 1, true) then return false end
    -- The Color Painter's scope picker only chooses what the painter previews;
    -- it starts nothing. Matched on the whole "/preview/scope/" segment rather
    -- than one leaf so the taxonomy can change (it went from one control per
    -- category to a single selector) without silently re-listing it as a
    -- launchable test mode.
    if path:find("/preview/scope/", 1, true) then return false end
    -- Two more families sit under a "preview" path segment without starting
    -- anything: the painter's palette swatches are colour values, and the
    -- preview pane's height toggle is window chrome. Both would otherwise be
    -- offered as runnable test modes because the marker matches the path.
    if path:find("/preview/palette/", 1, true) then return false end
    if path:find("/preview/height/", 1, true) then return false end
    -- Appearance's Aura-type selector chooses which product-specific dummy and
    -- settings are shown; it does not launch a preview mode.
    if path:find("auras/style/container/selector", 1, true) then return false end
    local text = " " .. ModeText(row) .. " "
    local marked = HasAny(text, MODE_MARKERS)
    if not marked then return false end
    return row.classification == "ephemeral" or row.actionKey ~= "" or row.safety == "nonStateful"
end

function Schema.ListModes(opts)
    opts = type(opts) == "table" and opts or {}
    local out, seen = {}, {}
    local contextId = opts.contextId or CurrentContextId()
    for _, row in ipairs(EnsureIndex().rows) do
        if Available(row, contextId) and IsLaunchableMode(row) then
            local copy = CopyRecord(row)
            copy.source = "control"
            out[#out + 1], seen[copy.actionKey ~= "" and ("action:" .. copy.actionKey) or copy.semanticId] = copy, true
        end
    end
    local Registry = A.Registry
    local actions = Registry and type(Registry.AllActions) == "function" and Registry:AllActions() or {}
    for i = 1, #(actions or {}) do
        local action = actions[i]
        local key = tostring(action and action.key or "")
        local text = Normalize(key .. " " .. tostring(action and action.label or "") .. " " .. tostring(action and action.type or ""))
        local marked = tostring(action and action.type or "") == "preview" or HasAny(" " .. text .. " ", MODE_MARKERS)
        if marked and not seen["action:" .. key] then
            seen["action:" .. key] = true
            out[#out + 1] = { source = "action", actionKey = key, label = action.label or key, kind = "action",
                pageKey = action.page or "", safety = action.confirmRequired and "confirm" or "direct", available = true }
        end
    end
    table.sort(out, function(left, right)
        local lp, rp = tostring(left.pageKey or ""), tostring(right.pageKey or "")
        if lp ~= rp then return lp < rp end
        return tostring(left.label or left.semanticId) < tostring(right.label or right.semanticId)
    end)
    return out
end

local function ModeListResult(normalized)
    if not HasAny(normalized, MODE_MARKERS) or not HasAny(normalized, MODE_LIST_TERMS) then return nil end
    local modes = Schema.ListModes()
    local showAll = HasAny(normalized, { "all", "every", "show all", "alle" })
    local limit = showAll and #modes or math.min(#modes, 12)
    local lines = { "I can start or open " .. tostring(#modes) .. " test and preview controls in your current context:" }
    for i = 1, limit do
        local mode = modes[i]
        local page = tostring(mode.pageKey or ""):gsub("_", " ")
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(mode.label or mode.semanticId)
            .. (page ~= "" and (" - " .. page) or "")
    end
    if limit < #modes then lines[#lines + 1] = "Ask 'list all test modes' to show the complete inventory." end
    return { text = table.concat(lines, "\n"), status = "info", summary = "MSUF test and preview modes", modes = modes }
end

local function ModeExecutionResult(text, normalized, top, confident)
    if not confident or not IsLaunchableMode(top) or not HasAny(normalized, MODE_MARKERS) then return nil end
    if not (HasAny(normalized, MODE_START_TERMS) or HasAny(normalized, MODE_OFF_TERMS) or HasAny(normalized, MODE_TOGGLE_TERMS)) then return nil end
    local opened, openMessage = Schema.Resolve(top.semanticId, { open = true })
    if not opened then
        return { text = tostring(openMessage or ("I could not open " .. tostring(top.label) .. ".")), status = "failed", summary = top.label }
    end
    local value
    if top.kind == "toggle" or top.kind == "segment" then
        if HasAny(normalized, MODE_OFF_TERMS) then value = false
        elseif HasAny(normalized, MODE_TOGGLE_TERMS) then
            local readOk, current = Schema.Read(top.semanticId)
            value = readOk and not (current == true) or true
        else value = true end
    end
    local ok, result = Schema.Execute(top.semanticId, value, { sourceText = text, open = false })
    if not ok then
        if type(result) == "table" then return result end
        local reason = result == "combat" and "That test has to wait until combat ends."
            or result == "confirmation_required" and "That test needs confirmation before it can start."
            or "I found and opened the control, but the test is not available in the current context."
        return { text = reason, status = "failed", summary = top.label }
    end
    if type(result) == "table" then return result end
    local verb = value == false and "Stopped" or "Started"
    return { text = verb .. " " .. tostring(top.label) .. " and focused its control.", status = "applied", summary = top.label }
end

local function DisplaySchemaValue(descriptor, value)
    if type(value) == "boolean" then return value and "enabled" or "disabled" end
    for i = 1, #(descriptor and descriptor.values or {}) do
        local row = descriptor.values[i]
        if row.value == value then return tostring(row.text or row.value) end
    end
    if type(value) == "table" then
        local r = tonumber(value.r ~= nil and value.r or value[1])
        local g = tonumber(value.g ~= nil and value.g or value[2])
        local b = tonumber(value.b ~= nil and value.b or value[3])
        local a = tonumber(value.a ~= nil and value.a or value[4])
        if r and g and b then
            local text = string.format("RGB %.3g, %.3g, %.3g", r, g, b)
            if a then text = text .. string.format(" (alpha %.3g)", a) end
            return text
        end
        return "a structured value"
    end
    return tostring(value)
end

local function ChoiceListResult(top)
    local values = top and top.values or {}
    if #values == 0 then
        return { text = tostring(top.label) .. " loads its choices from the current MSUF context. Open the control to inspect them.",
            status = "info", result = "info", summary = top.label }
    end
    local labels = {}
    for i = 1, math.min(#values, 24) do labels[#labels + 1] = tostring(values[i].text or values[i].value) end
    local suffix = #values > #labels and (" (and " .. tostring(#values - #labels) .. " more)") or ""
    return { text = tostring(top.label) .. " choices: " .. table.concat(labels, ", ") .. suffix .. ".",
        status = "info", result = "info", summary = top.label, values = values }
end

local function ExplainResult(top, wantsOpen)
    local lines = { tostring(top.label or "This control") .. ": " .. tostring(top.help or "MSUF exposes this control in its options.") }
    lines[#lines + 1] = "Location: " .. HumanPath(top) .. "."
    local readOk, current = Schema.Read(top.semanticId)
    if readOk then lines[#lines + 1] = "Current value: " .. DisplaySchemaValue(top, current) .. "." end
    if wantsOpen then
        local opened, message = Schema.Resolve(top.semanticId, { open = true })
        if opened then lines[#lines + 1] = tostring(message or ("Opened " .. tostring(top.label) .. ".")) end
    end
    return { text = table.concat(lines, "\n"), status = wantsOpen and "navigated" or "info",
        result = wantsOpen and "navigated" or "info", summary = top.label }
end

local function CurrentValueResult(top)
    local ok, value = Schema.Read(top.semanticId)
    if not ok then
        return { text = "I found " .. tostring(top.label) .. ", but its current value is not readable in this context. It is at "
                .. HumanPath(top) .. ".",
            status = "info", result = "read_unavailable", summary = top.label }
    end
    return { text = tostring(top.label) .. " is currently " .. DisplaySchemaValue(top, value) .. ".",
        status = "info", result = "info", summary = top.label, value = value }
end

-- Menu2 can render one exact control on several pages. Offering those mirrors
-- as rival choices -- or refusing because "more than one control matched" --
-- is noise about a value that still has exactly one product-specific home.
--
-- Identity has to be exact before two rows may merge: same path, name, widget,
-- value domain and setting key. The page must additionally be a plain menu
-- location. Unit pages ARE the scope (uf_pet and uf_targettarget share the path
-- unit/portrait/portraitborderstyle while owning different frames), so a
-- candidate on any of them blocks the merge outright.
local function CollapsePageMirrors(results)
    if #results < 2 then return results end
    local out, seen = {}, {}
    for i = 1, #results do
        local row = results[i]
        local pageKey = tostring(row.pageKey or "")
        if SCOPE_PAGES[pageKey] then
            out[#out + 1] = row
        else
            local identity = table.concat({
                tostring(row.controlPath or ""), tostring(row.label or ""),
                tostring(row.kind or ""), tostring(row.valueKind or ""),
                tostring(row.settingKey or ""), tostring(row.actionKey or ""),
                tostring(row.classification or ""), tostring(row.safety or ""),
                tostring(row.min or ""), tostring(row.max or ""),
            }, "\031")
            if not seen[identity] then
                seen[identity] = true
                out[#out + 1] = row
            end
        end
    end
    return out
end

-- Group pages hold one editor for Party, Raid and Mythic Raid; the scope is a
-- selector inside the page, not part of any control's indexed identity. So
-- "set the party spell icon zoom to 120" demanded a token no group row can ever
-- contain and found nothing, while the same request without "party" resolved
-- immediately.
--
-- Only runs after a normal search found nothing, and the surviving matches are
-- restricted to gf_* pages -- naming a group scope cannot silently land on a
-- unit-frame control.
local GROUP_SCOPE_PHRASES = {
    " mythic raid ", " mythicraid ", " party ", " raid ", " group ",
}

local function FindWithinGroupScope(query)
    local padded = " " .. Normalize(query) .. " "
    local stripped, found = padded, false
    for i = 1, #GROUP_SCOPE_PHRASES do
        local phrase = GROUP_SCOPE_PHRASES[i]
        if stripped:find(phrase, 1, true) then
            found = true
            stripped = stripped:gsub(phrase, " ")
        end
    end
    if not found then return {} end
    stripped = Trim(stripped)
    if stripped == "" then return {} end
    local out = {}
    for _, row in ipairs(Schema.Find(stripped, { limit = 8 })) do
        if tostring(row.pageKey or ""):sub(1, 3) == "gf_" then out[#out + 1] = row end
        if #out >= 4 then break end
    end
    return out
end

function Schema.TryConversation(text)
    local normalized = " " .. Normalize(text) .. " "
    local explicitNavigation = normalized:find(" open ", 1, true) or normalized:find(" oeffne ", 1, true)
        or normalized:find(" take me to ", 1, true) or normalized:find(" go to ", 1, true)
        or normalized:find(" navigate to ", 1, true) or normalized:find(" jump to ", 1, true)
        or normalized:find(" direct me to ", 1, true) or normalized:find(" show me ", 1, true)
        or normalized:find(" bring me to ", 1, true) or normalized:find(" fuehre mich zu ", 1, true)
    -- Compound unit names have dedicated dependency/troubleshooting owners in
    -- the router; generic token search must not split them into Target fields.
    -- Explicit control navigation is the exception because its canonical
    -- page/path identity disambiguates these unit names without mutation.
    if not explicitNavigation and (normalized:find(" target of target ", 1, true) or normalized:find(" targettarget ", 1, true)
        or normalized:find(" focus target ", 1, true) or normalized:find(" focustarget ", 1, true))
    then return nil end
    local modeList = not explicitNavigation and ModeListResult(normalized)
    if modeList then return modeList end
    local location = normalized:find(" where ", 1, true) or normalized:find(" find ", 1, true)
        or normalized:find(" wo ", 1, true) or normalized:find(" finde ", 1, true)
    local wantsOpen = explicitNavigation
    local wantsExplain = HasAny(normalized, { "explain", "describe", "tell me about", "what does", "why use",
        "erklaere", "beschreibe", "was macht", "wofuer" })
    local wantsChoices = HasAny(normalized, { "list choices", "list values", "available choices", "available values",
        "which choices", "which values", "what choices", "what values", "verfuegbare werte", "welche werte" })
    -- "what's" is spelled without its apostrophe here on purpose: Normalize
    -- strips punctuation before this comparison, so the contracted form only
    -- ever arrives as "whats".
    local wantsCurrent = HasAny(normalized, { "current value", "what is", "whats", "how is", "hows",
        "is currently", "configured to", "set to now",
        "aktueller wert", "welcher wert", "wie ist", "eingestellt auf" })
    local mutation = HasMutationIntent(normalized)
    local modeIntent = HasAny(normalized, MODE_MARKERS)
        and (HasAny(normalized, MODE_START_TERMS) or HasAny(normalized, MODE_OFF_TERMS) or HasAny(normalized, MODE_TOGGLE_TERMS))
    if not location and not wantsOpen and not mutation and not modeIntent and not wantsExplain and not wantsChoices and not wantsCurrent then return nil end

    -- This layer searches the generated catalog by token and has no idea what
    -- "it" refers to. When the request names its subject only by pronoun and the
    -- conversation still has a fresh one, the registry follow-up owns that
    -- reference -- letting a token search answer instead produced confidently
    -- wrong replies ("what is its separator" -> "Separator is currently 1",
    -- reading a Class Resource width slider). Standing down here costs nothing:
    -- this lane is consulted as a fallback, so the caller simply continues.
    do
        -- HasAny adds the surrounding spaces itself, so these are bare words.
        local pronounOnlySubject = HasAny(normalized, { "it", "its", "that", "this" })
        if pronounOnlySubject then
            local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
            if type(ctx) == "table" and type(ctx.lastSetting) == "string" and ctx.lastSetting ~= "" then
                local turn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0
                local subjectTurn = tonumber(ctx.lastSubjectTurn or ctx.lastMentionedTurn)
                local age = subjectTurn and (turn - subjectTurn) or nil
                if age and age >= 0 and age <= 3 then return nil end
            end
        end
    end

    local searchText, verblessText
    if mutation then
        searchText, verblessText = MutationTargetText(text)
    else
        searchText = text
        if explicitNavigation then
            local navigationTarget = Normalize(text):gsub("^please%s+", ""):gsub("^bitte%s+", "")
            navigationTarget = navigationTarget
                :gsub("^take me to%s+", ""):gsub("^go to%s+", ""):gsub("^navigate to%s+", "")
                :gsub("^jump to%s+", ""):gsub("^direct me to%s+", ""):gsub("^show me%s+", "")
                :gsub("^bring me to%s+", ""):gsub("^fuehre mich zu%s+", "")
                :gsub("^open%s+", ""):gsub("^oeffne%s+", "")
            if navigationTarget ~= "" then searchText = navigationTarget end
        end
    end
    local results = Schema.Find(searchText, { limit = 4 })
    if #results == 0 and verblessText then results = Schema.Find(verblessText, { limit = 4 }) end
    if #results == 0 then
        results = FindWithinGroupScope(searchText)
        if #results == 0 and verblessText then results = FindWithinGroupScope(verblessText) end
    end
    -- Parameterized actions and free-form values are sometimes written without
    -- an explicit "to" connector. Search never treats their arbitrary tail as
    -- control identity: trim one trailing token at a time only after the full
    -- query found nothing, then still require the normal confidence margin.
    local trimmed = false
    if mutation and #results == 0 then
        local tokens = {}
        for token in Normalize(searchText):gmatch("%S+") do tokens[#tokens + 1] = token end
        while #tokens > 2 and #results == 0 do
            table.remove(tokens)
            trimmed = true
            results = Schema.Find(table.concat(tokens, " "), { limit = 4 })
        end
    end
    if #results == 0 then return nil end
    results = CollapsePageMirrors(results)
    local top, second = results[1], results[2]
    local confident = (top._score or 0) >= 14 and (not second or (top._score or 0) - (second._score or 0) >= 6)

    -- Dropping words the player actually wrote is a guess, not a match. It may
    -- still identify one control outright, but it must never be dressed up as a
    -- shortlist: "change all unitframe borders" once answered with three
    -- unrelated Unitframes buttons because the noun had been trimmed away.
    if trimmed and not confident then return nil end

    -- "Take/show/direct me to" is always navigation, even when the control's
    -- own name contains Test or Preview. Starting transient UI still requires
    -- an execution request such as start/run/toggle outside that navigation
    -- form.
    if modeIntent and not wantsOpen then
        local modeResult = ModeExecutionResult(text, normalized, top, confident)
        if modeResult then return modeResult end
    end

    if confident and wantsChoices and not mutation then return ChoiceListResult(top) end
    if confident and wantsExplain and not mutation then return ExplainResult(top, wantsOpen and true or false) end
    if confident and wantsCurrent and not mutation then return CurrentValueResult(top) end

    if mutation and confident then
        local Registry, Parser = A.Registry, A.Parser
        if top.safety == "readOnly" or top.safety == "guided" then
            return { text = Schema.Render(top.safety, { label = top.label }), status = "info",
                result = top.safety, summary = top.label }
        end
        if top.actionKey ~= "" then
            return ExecuteSchemaAction(top, text)
        end
        local setting = top.settingKey ~= "" and Registry and Registry.GetSetting and Registry:GetSetting(top.settingKey) or nil
        if not setting then
            -- A Menu2 control with no hand-written Registry owner is not
            -- automatically menu-only. Schema.Execute owns the review gate for
            -- those (it demands a live catalog control with a vouched-for
            -- disposition, and wires snapshot/undo through ExecutePlan), so ask
            -- it instead of assuming. The shared aura icon border style and
            -- thickness are reachable no other way.
            local catalogBacked = top.classification == "setting" and top.settingKey == ""
                and (top.valueKind == "boolean" or top.valueKind == "number" or top.valueKind == "enum"
                    or top.valueKind == "string" or top.valueKind == "color")
            if (top.classification == "ephemeral" and top.safety == "nonStateful") or catalogBacked then
                local value, parsed = ParseDescriptorValue(top, text)
                if not parsed then
                    if not RequestNamesControl(normalized, top) then return nil end
                    return MissingDescriptorValue(top)
                end
                local ok, result = Schema.Execute(top.semanticId, value, { sourceText = text })
                if type(result) == "table" then return result end
                if ok then
                    return { text = "Applied " .. tostring(top.label) .. ".", status = "applied", result = "applied", summary = top.label }
                end
                -- Every refusal Schema.Execute raises for a catalog control
                -- means "not writable from here", not "broken". Say the same
                -- thing the guided lane says rather than reporting a fault.
                if CATALOG_GUIDED_RESULTS[tostring(result or "")] then
                    return { text = Schema.Render("guided", { label = top.label }), status = "info",
                        result = "guided", summary = top.label }
                end
                return { text = "I found " .. tostring(top.label) .. ", but it is not available right now.",
                    status = "failed", result = tostring(result or "failed"), summary = top.label }
            end
            return { text = Schema.Render("guided", { label = top.label }), status = "info", result = "guided", summary = top.label }
        end
        local value
        if Parser and type(Parser.ValueForRegistrySetting) == "function" then
            value = Parser.ValueForRegistrySetting(setting, Normalize(text), text)
        end
        if value == nil then
            -- No value AND no proof the player meant this control: "restyle the
            -- target castbar" is not a request to fill in Show Interrupt Ready
            -- on Target Castbar. Standing down lets the router's topic help --
            -- which knows the whole Cast Bars page -- answer instead.
            if not RequestNamesControl(normalized, top) then return nil end
            return MissingSettingValue(setting, top, text)
        end
        local ok, result = Schema.Execute(top.semanticId, value, { sourceText = text })
        if ok and type(result) == "table" then return result end
        if not ok and type(result) == "table" then return result end
        if result == "readOnly" or result == "guided" then
            return { text = Schema.Render(result, { label = top.label }), status = "info", summary = top.label }
        end
        if result == "stale_control" then
            return { text = Schema.Render("guided", { label = top.label }), status = "info", summary = top.label }
        end
        if result == "invalid_value" then return MissingSettingValue(setting, top, text) end
        return { text = "I found " .. tostring(top.label or setting.label) .. ", but the change could not be applied safely.",
            status = "failed", result = tostring(result or "failed"), summary = top.label or setting.label }
    end

    if (wantsOpen or location) and confident then
        local ok, message = Schema.Resolve(top.semanticId, { open = true })
        if ok then return { text = tostring(message or ("Opened " .. top.label .. ".")), status = "navigated", summary = top.label } end
    end

    local count = confident and 1 or math.min(#results, 3)

    -- An ambiguous mutation must offer a choice the player can actually answer.
    -- Reuse the shared pending-choice mechanism (A.SetPendingChoices) that the
    -- parser, router, diagnostics and workflows already share, so a numbered
    -- reply resolves here exactly as it does everywhere else.
    --
    -- Most controls that reach this lane are catalog-backed and have no
    -- registry owner at all, which is the whole reason the lane exists. Those
    -- are offered by semantic id and settled by Schema.Execute at selection
    -- time -- resolving them up front would have to open all three pages just
    -- to render a list.
    if mutation and not confident and count > 1 and type(A.SetPendingChoices) == "function" then
        local Registry, Parser = A.Registry, A.Parser
        -- Unpadded, matching the confident branch above; the outer `normalized`
        -- is space-padded for whole-phrase matching and is not what the value
        -- parser expects.
        local valueText = Normalize(text)
        -- Candidates in this lane routinely share one label ("Opacity" on three
        -- different aura pages). A numbered list of identical names is no more
        -- answerable than no list at all, so every entry carries the page that
        -- tells them apart.
        local function ChoiceBaseLabel(row)
            local label = tostring(DisplayLabel(row) ~= "" and DisplayLabel(row)
                or row.matchedValue or row.semanticId or "")
            local pageKey = tostring(row.pageKey or "")
            local page = type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(pageKey)
                or pageKey:gsub("_", " ")
            page = tostring(page or "")
            if label == "" then return page ~= "" and page or "Option" end
            if page == "" or label:find(page, 1, true) or page:find(label, 1, true) then return label end
            return label .. " - " .. page
        end

        local function ChoiceLabel(row, rowIndex)
            local label = ChoiceBaseLabel(row)
            for otherIndex = 1, count do
                if otherIndex ~= rowIndex and ChoiceBaseLabel(results[otherIndex]) == label then
                    local hint = DistinguishingSegment(row, results[otherIndex])
                    if hint ~= "" then return label .. " (" .. hint .. ")" end
                end
            end
            return label
        end

        local choices = {}
        for i = 1, count do
            local row = results[i]
            local label = ChoiceLabel(row, i)
            local settingKey = Trim(row.settingKey)
            local setting = settingKey ~= "" and Registry and type(Registry.GetSetting) == "function"
                and Registry:GetSetting(settingKey) or nil
            if setting then
                local value
                if Parser and type(Parser.ValueForRegistrySetting) == "function" then
                    value = Parser.ValueForRegistrySetting(setting, valueText, text)
                end
                if value ~= nil then
                    choices[#choices + 1] = { setting = setting, value = value, label = label }
                end
            elseif row.classification == "setting" and row.safety ~= "readOnly" and row.safety ~= "guided" then
                local value, parsed = ParseDescriptorValue(row, text)
                if parsed then
                    choices[#choices + 1] = {
                        schemaSemanticId = row.semanticId,
                        schemaSourceText = text,
                        value = value,
                        label = label,
                    }
                end
            end
        end
        -- All of them, or none: a partial list would silently drop a candidate
        -- the player was choosing between.
        if #choices == count then
            local choiceText = A.SetPendingChoices(choices)
            if choiceText then
                return { text = choiceText, status = "ambiguous", result = "ambiguous",
                    summary = "Ambiguous MSUF control" }
            end
        end
    end

    local lines, rendered = {}, {}
    for i = 1, count do
        local row = results[i]
        -- Name the control, then say where it lives. Leading with the matched
        -- value produced "No border is at Frames > Unitframes > Boss > Border",
        -- which reads as though the option were called "No border" -- it is one
        -- of its choices. The page breadcrumb alone avoids repeating the name.
        local displayLabel = DisplayLabel(row)
        if displayLabel == "" then displayLabel = row.matchedValue or row.semanticId end
        local body = tostring(displayLabel) .. " is at " .. PageBreadcrumb(row) .. "."
        -- Two controls can share a name on one page (Bars lists a Dispel
        -- trigger for the overlay and another for the symbol). A numbered list
        -- of identical lines answers nothing, so repeats earn the path segment
        -- that actually tells them apart.
        local clash = rendered[body]
        if clash then
            local hint = DistinguishingSegment(row, results[clash])
            if hint ~= "" then body = body:sub(1, -2) .. " (" .. hint .. ")." end
            local clashHint = DistinguishingSegment(results[clash], row)
            if clashHint ~= "" then
                lines[clash] = lines[clash]:sub(1, -2) .. " (" .. clashHint .. ")."
            end
        else
            rendered[body] = i
        end
        lines[#lines + 1] = (count == 1 and "" or (tostring(i) .. ". ")) .. body
    end
    if count > 1 then table.insert(lines, 1, "I found a few close controls:") end
    if mutation and not confident then
        -- No selectable owner, so the reply must not imply a number works.
        lines[#lines + 1] = "I kept MSUF unchanged because the request does not identify one control uniquely."
        lines[#lines + 1] = "Name the frame or page with the control, for example 'set player frame width to 250'."
        return { text = table.concat(lines, "\n"), status = "needs_choice", result = "needs_choice",
            summary = "Ambiguous MSUF control" }
    end
    return { text = table.concat(lines, "\n"), status = "info", result = "info", summary = "MSUF control location" }
end

function Schema.RegisterPack(locale, pack)
    locale = Trim(locale)
    if locale == "" or type(pack) ~= "table" then return false end
    Data.packs = Data.packs or {}
    Data.packs[locale] = pack
    return true
end

function Schema.Render(key, values, locale)
    locale = locale or (type(GetLocale) == "function" and GetLocale()) or "enUS"
    local packs = Data.packs or {}
    local template = (packs[locale] and packs[locale][key]) or (packs.enUS and packs.enUS[key]) or tostring(key or "")
    for name, value in pairs(type(values) == "table" and values or {}) do
        -- "%" is a capture reference on the REPLACEMENT side of gsub, so a
        -- label like "Icon Zoom (%)" -- RC9 added several -- came out as
        -- "Icon Zoom ()". Escape it so the control keeps its real name.
        local replacement = tostring(value):gsub("%%", "%%%%")
        template = template:gsub("{" .. tostring(name) .. "}", replacement)
    end
    return template
end

function Schema.Stats()
    return { version = Data.version, contexts = #(Data.contexts or {}), records = #(Data.records or {}), indexed = index ~= nil }
end
