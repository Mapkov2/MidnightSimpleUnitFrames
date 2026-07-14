-- Emits one deterministic union of every finite Menu2 Aura workspace state for
-- a configured desktop WoW context. The surrounding PowerShell generator runs
-- this in a fresh Lua process per class/spec so globals and page caches never
-- leak. The baseline is a complete catalog snapshot; every selector-dependent
-- snapshot after it is page-local so rebuilding one page cannot accidentally
-- erase or duplicate controls owned by another page.

_G = _G or _ENV

local function Read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local text = file:read("*a") or ""
    file:close()
    return text
end

local function Encode(value)
    if value == nil then return "" end
    local text = tostring(value)
    text = text:gsub("%%", "%%25")
        :gsub("\t", "%%09")
        :gsub("\r", "%%0D")
        :gsub("\n", "%%0A")
    return text
end

local function TypedValue(value)
    if type(value) == "boolean" then return value and "b:1" or "b:0" end
    if type(value) == "number" then return "n:" .. tostring(value) end
    return "s:" .. tostring(value or "")
end

local function CanonicalData(value, seen)
    local valueType = type(value)
    if value == nil then return "" end
    if valueType == "boolean" then return value and "b1" or "b0" end
    if valueType == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge,
            "non-finite number in serializable control metadata")
        return "n" .. string.format("%.17g", value)
    end
    if valueType == "string" then return "s" .. tostring(#value) .. ":" .. value end
    assert(valueType == "table", "non-serializable control metadata type " .. valueType)
    seen = seen or {}
    assert(not seen[value], "cycle in serializable control metadata")
    seen[value] = true
    local rows = {}
    for key, child in pairs(value) do
        local encodedKey = CanonicalData(key, seen)
        local encodedValue = CanonicalData(child, seen)
        rows[#rows + 1] = encodedKey .. "=" .. encodedValue
    end
    table.sort(rows)
    seen[value] = nil
    local encoded = {}
    for i = 1, #rows do encoded[#encoded + 1] = tostring(#rows[i]) .. ":" .. rows[i] end
    return "t" .. tostring(#rows) .. ":" .. table.concat(encoded)
end

local function SerializableInputDomain(value, seen, depth)
    local valueType = type(value)
    if value == nil or valueType == "boolean" or valueType == "string" or valueType == "number" then return value end
    if valueType ~= "table" then return nil end
    depth = (tonumber(depth) or 0) + 1
    assert(depth <= 12, "action input domain is too deep")
    seen = seen or {}
    assert(not seen[value], "cycle in action input domain")
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
            local copy = SerializableInputDomain(child, seen, depth)
            if copy ~= nil then out[key] = copy end
        end
    end
    seen[value] = nil
    return out
end

local VALUE_KIND_BY_CONTROL_KIND = {
    toggle = "boolean",
    slider = "number",
    dropdown = "enum",
    segment = "enum",
    color = "color",
    textinput = "string",
    button = "action",
    drag = "position",
    dragrow = "reorder",
}

local PAGE_LABELS = {
    auras3_buffs = "Auras > Buffs",
    auras3_custom = "Auras > Custom",
    auras3_debuffs = "Auras > Debuffs",
    auras3_filters = "Auras > Filters",
    auras3_styling = "Auras > Styling",
    classpower = "Class Resources",
    gameplay = "Gameplay",
    gf_auras = "Group Frames > Auras",
    gf_bars = "Group Frames > Bars",
    gf_indicators = "Group Frames > Indicators",
    gf_layout = "Group Frames > Layout",
    guided_setup = "Guided Setup",
    home = "MSUF Home",
    menu_chrome = "MSUF Menu",
    modules = "Modules",
    opt_bars = "Global Bars",
    opt_castbar = "Cast Bars",
    opt_colors = "Global Colors",
    opt_fonts = "Global Fonts",
    opt_misc = "Global Miscellaneous",
    profiles = "Profiles",
    uf_boss = "Boss Unit Frame",
    uf_focus = "Focus Unit Frame",
    uf_focustarget = "Focus Target Unit Frame",
    uf_pet = "Pet Unit Frame",
    uf_player = "Player Unit Frame",
    uf_target = "Target Unit Frame",
    uf_targettarget = "Target of Target Unit Frame",
}

local function CleanText(value)
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    value = tostring(value):gsub("%s+", " ")
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function FirstText(...)
    for i = 1, select("#", ...) do
        local value = CleanText(select(i, ...))
        if value ~= "" then return value end
    end
    return ""
end

local function Sentence(value)
    value = CleanText(value)
    if value == "" or value:match("[%.!?]$") then return value end
    return value .. "."
end

local function PrettyToken(value)
    value = CleanText(value)
    value = value:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
        :gsub("[_%-/]+", " "):gsub("%s+", " ")
    return (value:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local function ControlPathLabel(controlPath)
    local segments = {}
    for segment in CleanText(controlPath):gmatch("[^/]+") do segments[#segments + 1] = segment end
    local count = #segments
    if count == 0 then return "" end
    local last = segments[count]:lower()
    local known = {
        offlinealpha = "Offline Opacity",
        rangefadealpha = "Range Fade Opacity",
        framescalemanual = "Manual Frame Scale",
        scaleat10 = "Scale at 10 Players",
        scaleat20 = "Scale at 20 Players",
        scaleat25 = "Scale at 25 Players",
        scaleover25 = "Scale over 25 Players",
    }
    if known[last] then return known[last] end
    if last == "strata" and count > 1 then return PrettyToken(segments[count - 1] .. " strata") end
    local channel = { r = "Red", g = "Green", b = "Blue", a = "Alpha" }
    if channel[last] then
        local previous = count > 1 and segments[count - 1] or ""
        if previous:lower() == "bg" then previous = "Background" end
        local owner = count > 2 and segments[count - 2] or ""
        return PrettyToken((owner ~= "" and (owner .. " ") or "") .. previous) .. " " .. channel[last]
    end
    if last == "alpha" and count > 2 then
        return PrettyToken(segments[count - 2] .. " " .. segments[count - 1] .. " alpha")
    end
    if count > 1 and (last == "x" or last == "y") then
        return PrettyToken(segments[count - 1] .. " " .. last)
    end
    return PrettyToken(segments[count])
end

local function PageLabel(pageKey)
    pageKey = CleanText(pageKey)
    if PAGE_LABELS[pageKey] then return PAGE_LABELS[pageKey] end
    local pretty = PrettyToken(pageKey)
    return pretty ~= "" and pretty or "MSUF options"
end

local function ResolveValueKind(descriptor)
    descriptor = type(descriptor) == "table" and descriptor or {}
    local explicit = CleanText(descriptor.valueKind)
    if explicit ~= "" then return explicit end
    local kind = CleanText(descriptor.kind):lower()
    return VALUE_KIND_BY_CONTROL_KIND[kind] or "value"
end

local function FormatScalar(value)
    if type(value) == "number" then return string.format("%.12g", value) end
    return CleanText(value)
end

local function EnumSummary(values)
    if type(values) ~= "table" or #values == 0 then return "" end
    local labels, seen, total = {}, {}, 0
    for i = 1, #values do
        local row = values[i]
        local label = type(row) == "table" and FirstText(row.text, row.label, row.value) or CleanText(row)
        if label ~= "" and not seen[label] then
            seen[label], total = true, total + 1
            if #labels < 8 then labels[#labels + 1] = label end
        end
    end
    if #labels == 0 then return "" end
    local suffix = total > #labels and (" (and " .. tostring(total - #labels) .. " more)") or ""
    return table.concat(labels, ", ") .. suffix
end

local function ResolveHelp(descriptor, setting, action, safety)
    descriptor = type(descriptor) == "table" and descriptor or {}
    setting = type(setting) == "table" and setting or {}
    action = type(action) == "table" and action or {}

    local existing = CleanText(descriptor.help)
    if existing ~= "" then return existing end

    local label = FirstText(descriptor.label, setting.label, action.label, setting.key, action.key,
        ControlPathLabel(descriptor.controlPath), descriptor.semanticId, "control")
    label = label:gsub("%s*:%s*$", "")
    local kind = CleanText(descriptor.kind):lower()
    local description = FirstText(setting.description, setting.summary, setting.help,
        action.description, action.summary, action.help)
    local parts = {}
    if description ~= "" then
        parts[#parts + 1] = Sentence(description)
    elseif kind == "toggle" then
        parts[#parts + 1] = "Turns " .. label .. " on or off."
    elseif kind == "slider" then
        parts[#parts + 1] = "Adjusts " .. label .. "."
    elseif kind == "dropdown" or kind == "segment" then
        parts[#parts + 1] = "Selects " .. label .. "."
    elseif kind == "color" then
        parts[#parts + 1] = "Chooses the color used by " .. label .. "."
    elseif kind == "textinput" then
        parts[#parts + 1] = "Edits the text used by " .. label .. "."
    elseif kind == "drag" then
        parts[#parts + 1] = "Moves " .. label .. "."
    elseif kind == "dragrow" then
        parts[#parts + 1] = "Reorders " .. label .. "."
    elseif descriptor.classification == "navigation" then
        parts[#parts + 1] = "Opens " .. label .. "."
    else
        parts[#parts + 1] = "Runs " .. label .. "."
    end

    parts[#parts + 1] = "Available on the " .. PageLabel(descriptor.pageKey) .. " page."
    if kind == "slider" then
        local minimum, maximum, step = FormatScalar(descriptor.min), FormatScalar(descriptor.max), FormatScalar(descriptor.step)
        if minimum ~= "" and maximum ~= "" then
            local range = "Allowed range: " .. minimum .. " to " .. maximum
            if step ~= "" then range = range .. " in increments of " .. step end
            parts[#parts + 1] = range .. "."
        end
    elseif kind == "dropdown" or kind == "segment" then
        local choices = EnumSummary(descriptor.values)
        -- Workspace selectors intentionally expose different choices after a
        -- parent selector changes. Their merged values carry the complete
        -- domain; keep prose state-invariant so metadata drift remains a real
        -- identity error instead of a rendering artifact.
        if descriptor.classification == "ephemeral" then
            parts[#parts + 1] = "Choices load from the current MSUF context."
        else
            parts[#parts + 1] = choices ~= "" and ("Available choices: " .. choices .. ".")
                or "Choices load from the current MSUF context."
        end
    elseif ResolveValueKind(descriptor) == "text" then
        parts[#parts + 1] = "Requires a text value."
    end

    if safety == "guided" then
        parts[#parts + 1] = "The Assistant guides to this control instead of changing it automatically."
    elseif safety == "readOnly" then
        parts[#parts + 1] = "This control is available for inspection only."
    elseif safety == "confirm" then
        parts[#parts + 1] = "The Assistant requires confirmation before changing it."
    end
    return table.concat(parts, " ")
end

local contextId = tostring(arg[1] or os.getenv("MSUF_TEST_CONTEXT_ID") or "MAGE-62")
local classToken = tostring(os.getenv("MSUF_TEST_CLASS_TOKEN") or "MAGE")
local specIndex = tonumber(os.getenv("MSUF_TEST_SPEC_INDEX")) or 1

local collectionStates, collectionStateById, collectionUnion = {}, {}, {}

local function DescriptorFields(descriptor, Registry)
    local setting = descriptor.settingKey and Registry:GetSetting(descriptor.settingKey) or nil
    local action = descriptor.actionKey and Registry:GetAction(descriptor.actionKey) or nil
    local safety = descriptor.safety or "readOnly"
    if setting then
        if setting.generated == true and setting.assistantMutationSafe ~= true then safety = "readOnly" end
        if type(setting.get) ~= "function" or type(setting.set) ~= "function" then safety = "readOnly" end
        if setting.confirmRequired == true and safety ~= "readOnly" then safety = "confirm" end
    elseif action then
        if action.mutability == "readOnly" then safety = "readOnly"
        elseif action.mutability == "navigation" or action.mutability == "ephemeral" then safety = "nonStateful"
        elseif action.confirmRequired == true then safety = "confirm" end
        local contract = action.assistantInput
        local inputArg = CleanText(descriptor.actionInputArg)
        local fixedArgs = descriptor.actionFixedArgs
        local acceptsNoArgs = type(contract) == "table" and (contract.kind == "none"
            or (#(contract.required or {}) == 0 and #(contract.requireAny or {}) == 0))
        local hasFixedArgs = type(fixedArgs) == "table" and next(fixedArgs) ~= nil
        local hasTypedInput = inputArg ~= "" and type(contract) == "table"
            and type(contract.fields) == "table" and type(contract.fields[inputArg]) == "table"
        local hasNaturalParser = type(action.parseAliasArgs) == "function"
        if action.assistantInputExplicit ~= true or type(contract) ~= "table"
            or (not acceptsNoArgs and not hasFixedArgs and not hasTypedInput and not hasNaturalParser)
        then
            safety = "guided"
        elseif safety == "guided" then
            safety = action.confirmRequired == true and "confirm" or "direct"
        end
    end
    if not setting and not action and descriptor.classification == "setting"
        and (descriptor.assistantDisposition == "dynamic" or descriptor.assistantDisposition == "compound"
            or descriptor.assistantDisposition == "duplicate")
    then
        local valueKind = ResolveValueKind(descriptor)
        if valueKind == "boolean" or valueKind == "number" or valueKind == "enum"
            or valueKind == "string" or valueKind == "color"
        then safety = descriptor.confirmRequired == true and "confirm" or "direct" end
    end
    if descriptor.classification == "unknown" then safety = "readOnly" end

    local values = {}
    for v = 1, #(descriptor.values or {}) do
        local row = descriptor.values[v]
        values[#values + 1] = TypedValue(row.value) .. "\030" .. tostring(row.text or row.value or "")
    end

    local storageUnit = CleanText(descriptor.storageUnit)
    local displayUnit = CleanText(descriptor.displayUnit)
    local displayScale = descriptor.displayScale
    if setting and setting.percent == true then
        if storageUnit == "" then storageUnit = "fraction" end
        if displayUnit == "" then displayUnit = "percent" end
        if displayScale == nil or displayScale == "" then displayScale = 100 end
    end

    local actionInputArg = CleanText(descriptor.actionInputArg)
    local actionInputKind = CleanText(descriptor.actionInputKind)
    local actionInputDomain = descriptor.actionInputDomain
    if action and actionInputArg ~= "" then
        local contract = action.assistantInput
        assert(type(contract) == "table" and type(contract.fields) == "table"
            and type(contract.fields[actionInputArg]) == "table",
            "action input field " .. actionInputArg .. " is absent from contract " .. tostring(action.key))
        actionInputDomain = actionInputDomain or SerializableInputDomain(contract.fields[actionInputArg])
        if actionInputKind == "" then actionInputKind = CleanText(contract.fields[actionInputArg].type) end
    end

    local label = FirstText(descriptor.label,
        setting and setting.label, action and action.label,
        ControlPathLabel(descriptor.controlPath), descriptor.semanticId, "MSUF control")

    return {
        descriptor.semanticId or "", descriptor.controlId or "", descriptor.familyId or "", descriptor.memberKey or "",
        descriptor.pageKey or "", descriptor.controlPath or "", descriptor.classification or "", descriptor.kind or "",
        descriptor.settingKey or "", descriptor.actionKey or "", descriptor.navigationKey or "", safety or "readOnly",
        ResolveValueKind(descriptor), descriptor.min or "", descriptor.max or "", descriptor.step or "",
        descriptor.percentIsValue == true and "1" or "0",
        descriptor.confirmRequired == true and "1" or "0",
        descriptor.identityStable == true and "1" or "0",
        label, ResolveHelp(descriptor, setting, action, safety), table.concat(values, "\031"),
        CanonicalData(descriptor.actionFixedArgs), actionInputArg,
        actionInputKind, CanonicalData(actionInputDomain),
        storageUnit, displayUnit, displayScale or "",
    }
end

local function MergeValues(left, right)
    local seen, values = {}, {}
    for _, encoded in ipairs({ left, right }) do
        for value in tostring(encoded or ""):gmatch("[^\031]+") do
            if not seen[value] then seen[value], values[#values + 1] = true, value end
        end
    end
    return table.concat(values, "\031")
end

local function MergeDescriptorFields(existing, incoming, stateId)
    -- semanticId through identityStable define one executable control. A
    -- state-dependent change here means the catalog identity is not stable
    -- enough to union safely and must fail generation rather than overwrite.
    for field = 1, 19 do
        assert(tostring(existing[field] or "") == tostring(incoming[field] or ""),
            "semantic identity drift for " .. tostring(existing[1]) .. " in state " .. tostring(stateId)
                .. " at field " .. tostring(field))
    end
    -- Labels/help may become available only after a live selector is routed,
    -- but two conflicting non-empty descriptions for one semantic ID are not
    -- safe to collapse.
    for field = 20, 21 do
        local old, new = tostring(existing[field] or ""), tostring(incoming[field] or "")
        assert(old == "" or new == "" or old == new,
            "semantic metadata drift for " .. tostring(existing[1]) .. " in state " .. tostring(stateId)
                .. " at field " .. tostring(field))
        if old == "" and new ~= "" then existing[field] = incoming[field] end
    end
    existing[22] = MergeValues(existing[22], incoming[22])
    -- Serializable action contracts and numeric storage/display domains are
    -- part of semantic meaning. A state-dependent change must never be merged.
    for field = 23, 29 do
        assert(tostring(existing[field] or "") == tostring(incoming[field] or ""),
            "semantic contract drift for " .. tostring(existing[1]) .. " in state " .. tostring(stateId)
                .. " at field " .. tostring(field))
    end
end

local function CaptureAssistantControlSchemaState(stateId, Catalog, Registry, pageKey)
    stateId = CleanText(stateId)
    pageKey = CleanText(pageKey)
    assert(stateId ~= "", "control-schema collection state is missing an ID")
    assert(not collectionStateById[stateId], "duplicate control-schema collection state " .. stateId)
    local descriptors = assert(Catalog.GetAssistantDescriptors,
        "RuntimeControlCatalog.GetAssistantDescriptors is missing")()
    local selected = {}
    for i = 1, #descriptors do
        local descriptor = descriptors[i]
        if pageKey == "" or tostring(descriptor and descriptor.pageKey or "") == pageKey then
            selected[#selected + 1] = descriptor
        end
    end
    local state = { id = stateId, pageKey = pageKey, count = #selected, semanticIds = {} }
    collectionStates[#collectionStates + 1], collectionStateById[stateId] = state, state
    for i = 1, #selected do
        local fields = DescriptorFields(selected[i], Registry)
        local semanticId = tostring(fields[1] or "")
        assert(semanticId ~= "", "control-schema descriptor in state " .. stateId .. " has no semantic ID")
        assert(not state.semanticIds[semanticId],
            "duplicate semantic ID " .. semanticId .. " inside collection state " .. stateId)
        state.semanticIds[semanticId] = true
        local record = collectionUnion[semanticId]
        if not record then
            record = { fields = fields, states = {} }
            collectionUnion[semanticId] = record
        else
            MergeDescriptorFields(record.fields, fields, stateId)
        end
        record.states[stateId] = true
    end
    return state.count
end

local UNIT_PAGES = {
    { unit = "player", page = "uf_player" },
    { unit = "target", page = "uf_target" },
    { unit = "focus", page = "uf_focus" },
    { unit = "boss", page = "uf_boss" },
}
local NORMAL_UNIT_TOOLS = { "layout", "filters", "blacklist" }
local CUSTOM_UNIT_TOOLS = { "setup", "layout", "filters", "whitelist" }
local GROUP_SCOPES = { "party", "raid", "mythicraid" }
local STYLE_SCOPES = { "shared", "player", "target", "focus", "boss", "party", "raid" }

local function EnsureTable(owner, key)
    local value = owner[key]
    if type(value) ~= "table" then value = {}; owner[key] = value end
    return value
end

local function RebuildCollectionPage(M, pageKey)
    assert(type(M.InvalidatePage) == "function", "real Menu2 page invalidation API did not load")
    assert(type(M.BuildPageEntry) == "function", "real Menu2 page builder API did not load")
    M.InvalidatePage(pageKey)
    local ok, result = pcall(M.BuildPageEntry, pageKey, true)
    assert(ok, "control-schema state failed to build " .. tostring(pageKey) .. ": " .. tostring(result))
    assert(result ~= nil, "control-schema state did not produce a page entry for " .. tostring(pageKey))
end

local function SetUnitAuraState(M, unit, container, tool)
    EnsureTable(M, "unitAuraTabSelection")[unit] = container
    local unitTools = EnsureTable(EnsureTable(M, "unitAuraToolSelection"), unit)
    unitTools[container] = tool
end

local function SetGroupAuraState(M, scope, lane, tool)
    M.gfScope = scope
    EnsureTable(M, "gfAuraLaneSelection")[scope] = lane
    local scopeTools = EnsureTable(EnsureTable(M, "gfAuraToolSelection"), scope)
    scopeTools[lane] = tool
end

local function SetStyleState(M, scope, container)
    M.auraScope = scope
    M.auraStyleContainer = container
    if container == "buff" or container == "debuff" then M.auraStyleGFLane = container end
end

local function CollectAssistantControlSchemaStates(M, Catalog, Registry)
    assert(#collectionStates == 0, "control-schema states were already collected")
    local model = assert(_G.MSUF_NS and _G.MSUF_NS.MSUF_Auras3
        and _G.MSUF_NS.MSUF_Auras3.MenuModel, "Auras3 MenuModel is missing")

    -- Establish one explicit baseline independent of whatever selector routes
    -- the crosswalk exercised while proving reverse parity.
    for i = 1, #UNIT_PAGES do
        local row = UNIT_PAGES[i]
        SetUnitAuraState(M, row.unit, "buff", "layout")
        SetUnitAuraState(M, row.unit, "debuff", "layout")
        for index = 1, 3 do
            local container = "custom" .. tostring(index)
            SetUnitAuraState(M, row.unit, container, "setup")
            local item = assert(model.CustomContainer(row.unit, index, true),
                "missing custom Aura container for " .. row.unit .. " " .. tostring(index))
            item.auraType = "BUFF"
        end
        M.unitAuraTabSelection[row.unit] = "buff"
    end
    for i = 1, #GROUP_SCOPES do SetGroupAuraState(M, GROUP_SCOPES[i], "buff", "layout") end
    M.gfScope = "party"
    SetStyleState(M, "shared", "debuff")

    for i = 1, #UNIT_PAGES do RebuildCollectionPage(M, UNIT_PAGES[i].page) end
    RebuildCollectionPage(M, "gf_auras")
    RebuildCollectionPage(M, "auras3_styling")
    RebuildCollectionPage(M, "auras3_buffs")
    RebuildCollectionPage(M, "auras3_debuffs")
    CaptureAssistantControlSchemaState("base", Catalog, Registry)

    -- Four units x (two native lanes x three tools + three custom lanes x
    -- four tools) = 72 finite unit-frame Aura workspace states.
    for i = 1, #UNIT_PAGES do
        local row = UNIT_PAGES[i]
        for _, container in ipairs({ "buff", "debuff" }) do
            for _, tool in ipairs(NORMAL_UNIT_TOOLS) do
                SetUnitAuraState(M, row.unit, container, tool)
                RebuildCollectionPage(M, row.page)
                CaptureAssistantControlSchemaState(
                    "unit_" .. row.unit .. "_" .. container .. "_" .. tool,
                    Catalog, Registry, row.page)
            end
        end
        for index = 1, 3 do
            local container = "custom" .. tostring(index)
            for _, tool in ipairs(CUSTOM_UNIT_TOOLS) do
                SetUnitAuraState(M, row.unit, container, tool)
                RebuildCollectionPage(M, row.page)
                CaptureAssistantControlSchemaState(
                    "unit_" .. row.unit .. "_" .. container .. "_" .. tool,
                    Catalog, Registry, row.page)
            end
        end

        -- Custom filter controls have a second finite branch by Aura type.
        -- One custom container per unit is sufficient because these controls
        -- are one selector-bound semantic family and the branch shape is equal
        -- for Custom 1-3.
        local item = assert(model.CustomContainer(row.unit, 1, true),
            "missing custom Aura container for " .. row.unit .. " 1")
        item.auraType = "DEBUFF"
        SetUnitAuraState(M, row.unit, "custom1", "filters")
        RebuildCollectionPage(M, row.page)
        CaptureAssistantControlSchemaState(
            "unit_" .. row.unit .. "_custom1_filters_debuff",
            Catalog, Registry, row.page)
        item.auraType = "BUFF"
    end

    -- Three group scopes x (two native lanes x three tools + one external
    -- lane x layout) = 21 finite group Aura workspace states.
    for _, scope in ipairs(GROUP_SCOPES) do
        for _, lane in ipairs({ "buff", "debuff" }) do
            for _, tool in ipairs(NORMAL_UNIT_TOOLS) do
                SetGroupAuraState(M, scope, lane, tool)
                RebuildCollectionPage(M, "gf_auras")
                CaptureAssistantControlSchemaState(
                    "gf_" .. scope .. "_" .. lane .. "_" .. tool,
                    Catalog, Registry, "gf_auras")
            end
        end
        SetGroupAuraState(M, scope, "externals", "layout")
        RebuildCollectionPage(M, "gf_auras")
        CaptureAssistantControlSchemaState(
            "gf_" .. scope .. "_externals_layout", Catalog, Registry, "gf_auras")
    end

    -- Shared and group scopes expose two lanes; four unit scopes expose those
    -- lanes plus Custom 1-3. This is the complete 26-state style matrix.
    for _, scope in ipairs(STYLE_SCOPES) do
        local containers = (scope == "player" or scope == "target" or scope == "focus" or scope == "boss")
            and { "buff", "debuff", "custom1", "custom2", "custom3" }
            or { "buff", "debuff" }
        for _, container in ipairs(containers) do
            SetStyleState(M, scope, container)
            RebuildCollectionPage(M, "auras3_styling")
            CaptureAssistantControlSchemaState(
                "style_" .. scope .. "_" .. container,
                Catalog, Registry, "auras3_styling")
        end
    end

    -- These pages remain registered compatibility landings and build the real
    -- scope-dependent editor. Capture both pages for all seven legal scopes so
    -- their search/navigation surface cannot silently lag the canonical page.
    for _, scope in ipairs(STYLE_SCOPES) do
        for _, lane in ipairs({ "buff", "debuff" }) do
            local page = lane == "buff" and "auras3_buffs" or "auras3_debuffs"
            SetStyleState(M, scope, lane)
            RebuildCollectionPage(M, page)
            CaptureAssistantControlSchemaState(
                "compat_" .. lane .. "_" .. scope, Catalog, Registry, page)
        end
    end

    assert(#collectionStates == 138,
        "finite control-schema matrix drifted: expected 138 states, got " .. tostring(#collectionStates))
    return true
end

local function CollectionStateMembership(record)
    local ids = {}
    for i = 1, #collectionStates do
        local stateId = collectionStates[i].id
        if record.states[stateId] then ids[#ids + 1] = stateId end
    end
    if #ids == #collectionStates then return "*" end
    return table.concat(ids, ",")
end

local function EmitAssistantControlSchema()
    assert(#collectionStates == 138, "control-schema collection did not capture the complete finite state matrix")
    local specId, specName = _G.GetSpecializationInfo and _G.GetSpecializationInfo(specIndex)
    print(table.concat({ "CONTEXT", Encode(contextId), Encode(classToken), Encode(specIndex),
        Encode(specId), Encode(specName), Encode(_G.GetLocale and _G.GetLocale() or "enUS") }, "\t"))
    for i = 1, #collectionStates do
        local state = collectionStates[i]
        print(table.concat({ "STATE", Encode(state.id), Encode(state.count) }, "\t"))
    end
    local semanticIds = {}
    for semanticId in pairs(collectionUnion) do semanticIds[#semanticIds + 1] = semanticId end
    table.sort(semanticIds)
    print(table.concat({ "UNION", Encode(#semanticIds) }, "\t"))
    for i = 1, #semanticIds do
        local record = collectionUnion[semanticIds[i]]
        local fields = { "RECORD" }
        for f = 1, #record.fields do fields[#fields + 1] = record.fields[f] end
        fields[#fields + 1] = CollectionStateMembership(record)
        for f = 1, #fields do fields[f] = Encode(fields[f]) end
        print(table.concat(fields, "\t"))
    end
end

_G.__MSUF_CaptureAssistantControlSchemaState = CaptureAssistantControlSchemaState
_G.__MSUF_CollectAssistantControlSchemaStates = CollectAssistantControlSchemaStates
_G.__MSUF_EmitAssistantControlSchema = EmitAssistantControlSchema

local source = Read("tools/assistant_v1_catalog_crosswalk.lua")
source = source .. '\n__MSUF_CollectAssistantControlSchemaStates(M, Catalog, Registry)\n'
    .. '__MSUF_EmitAssistantControlSchema()\n'
local chunk, err = loadstring(source, "@tools/assistant_v1_catalog_crosswalk.lua")
assert(chunk, err)
local previousGraphifySource = rawget(_G, "__MSUF_ASSISTANT_GRAPHIFY_SOURCE")
_G.__MSUF_ASSISTANT_GRAPHIFY_SOURCE = "inventory"
local ok, result = pcall(chunk)
_G.__MSUF_ASSISTANT_GRAPHIFY_SOURCE = previousGraphifySource
assert(ok, result)
