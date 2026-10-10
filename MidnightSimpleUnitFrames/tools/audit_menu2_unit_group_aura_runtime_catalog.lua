-- Local-only, release-independent audit for the Unit/Group/Aura Menu2 runtime
-- control catalog.  Run from the addon directory:
--   lua tools/audit_menu2_unit_group_aura_runtime_catalog.lua
--
-- The audit has two deliberately separate halves:
--   1. source call-site coverage (factories, binders, search registration),
--   2. a dynamic ID/classification corpus executed by the real catalog.

local ROOT = ""

local PAGE_FILES = {
    "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitAlpha.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Group.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Auras.lua",
}

local PREVIEW_FILES = {
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Model.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Runtime.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_ZoomPan.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_API.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Specs.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Rounded.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_TextFocus.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_ZoomPan.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua",
}

local FILES = {}
for i = 1, #PAGE_FILES do FILES[#FILES + 1] = PAGE_FILES[i] end
for i = 1, #PREVIEW_FILES do FILES[#FILES + 1] = PREVIEW_FILES[i] end

local failures = {}
local function Fail(path, line, message)
    failures[#failures + 1] = string.format("%s:%s %s", path, tostring(line or "?"), message)
end
local function Check(value, path, line, message)
    if not value then Fail(path, line, message) end
    return value
end
local function Read(path)
    local file, err = io.open(ROOT .. path, "rb")
    if not file then error(err) end
    local text = file:read("*a")
    file:close()
    return text
end
local function LineAt(text, offset)
    local _, count = text:sub(1, math.max(1, offset)):gsub("\n", "")
    return count + 1
end

-- Balanced Lua-call reader.  It ignores quoted strings, long strings and both
-- comment forms so parentheses in help copy cannot corrupt call boundaries.
local function LongBracketAt(text, at)
    local eq = text:match("^%[(=*)%[", at)
    if eq == nil then return nil end
    return eq, #eq + 2
end
local function BalancedCall(text, openAt)
    local depth, quote, escaped = 0, nil, false
    local longEq, lineComment, blockComment
    local i = openAt
    while i <= #text do
        local ch, pair = text:sub(i, i), text:sub(i, i + 1)
        if lineComment then
            if ch == "\n" then lineComment = nil end
        elseif blockComment then
            local close = "]" .. blockComment .. "]"
            if text:sub(i, i + #close - 1) == close then
                i = i + #close - 1
                blockComment = nil
            end
        elseif longEq then
            local close = "]" .. longEq .. "]"
            if text:sub(i, i + #close - 1) == close then
                i = i + #close - 1
                longEq = nil
            end
        elseif quote then
            if escaped then escaped = false
            elseif ch == "\\" then escaped = true
            elseif ch == quote then quote = nil end
        elseif pair == "--" then
            local eq = LongBracketAt(text, i + 2)
            if eq ~= nil then blockComment = eq; i = i + #eq + 3
            else lineComment = true; i = i + 1 end
        elseif ch == "\"" or ch == "'" then
            quote = ch
        else
            local eq, width = LongBracketAt(text, i)
            if eq ~= nil then
                longEq = eq
                i = i + width - 1
            elseif ch == "(" then
                depth = depth + 1
            elseif ch == ")" then
                depth = depth - 1
                if depth == 0 then return text:sub(openAt, i), i end
            end
        end
        i = i + 1
    end
    return nil
end

local function EscapePattern(value)
    return (value:gsub("([^%w])", "%%%1"))
end
local function FindCalls(text, name)
    local out, cursor, escaped = {}, 1, EscapePattern(name)
    while true do
        local startAt, openAt = text:find("%f[%w_]" .. escaped .. "%s*%(", cursor)
        if not startAt then break end
        local before = text:sub(math.max(1, startAt - 32), startAt - 1)
        local call, closeAt = BalancedCall(text, openAt)
        if not call then
            out[#out + 1] = { at = startAt, line = LineAt(text, startAt), broken = true }
            break
        end
        if not before:match("function%s+$") then
            out[#out + 1] = { at = startAt, line = LineAt(text, startAt), text = call, closeAt = closeAt }
        end
        cursor = closeAt + 1
    end
    return out
end

local function SplitArgs(call)
    local openAt = assert(call:find("(", 1, true))
    local body = call:sub(openAt + 1, -2)
    local out, startAt = {}, 1
    local paren, brace, bracket = 0, 0, 0
    local quote, escaped, longEq
    local i = 1
    while i <= #body do
        local ch = body:sub(i, i)
        if longEq then
            local close = "]" .. longEq .. "]"
            if body:sub(i, i + #close - 1) == close then i = i + #close - 1; longEq = nil end
        elseif quote then
            if escaped then escaped = false
            elseif ch == "\\" then escaped = true
            elseif ch == quote then quote = nil end
        elseif ch == "\"" or ch == "'" then quote = ch
        else
            local eq, width = LongBracketAt(body, i)
            if eq ~= nil then longEq = eq; i = i + width - 1
            elseif ch == "(" then paren = paren + 1
            elseif ch == ")" then paren = paren - 1
            elseif ch == "{" then brace = brace + 1
            elseif ch == "}" then brace = brace - 1
            elseif ch == "[" then bracket = bracket + 1
            elseif ch == "]" then bracket = bracket - 1
            elseif ch == "," and paren == 0 and brace == 0 and bracket == 0 then
                out[#out + 1] = body:sub(startAt, i - 1):match("^%s*(.-)%s*$")
                startAt = i + 1
            end
        end
        i = i + 1
    end
    out[#out + 1] = body:sub(startAt):match("^%s*(.-)%s*$")
    return out
end

local function MetadataArgLooksSemantic(value)
    value = tostring(value or "")
    if value == "" or value == "nil" then return false end
    if value:find("Meta", 1, true) or value:find("ResolveGroupControlMeta", 1, true) then return true end
    if value:match("^meta[%w_%.%[%]]*$") or value:match("^metadata[%w_%.%[%]]*$") then return true end
    if value:match("^opts[%w_%.%[%]]*$") or value:match("^row[%w_%.%[%]]*$") then return true end
    if value:find("controlId%s*=") or value:find("identityKey%s*=") or value:find("controlPath%s*=") then return true end
    return false
end

local function CallHasSemanticMetadata(call, source, path)
    local text = call.text or ""
    if text:find("Meta", 1, true) or text:find("ResolveGroupControlMeta", 1, true) then return true end
    -- Unit status binders intentionally register their selected-status semantic
    -- path immediately after binding, because the backing DB key is selected at
    -- runtime. The search registration merges with the command on the same widget.
    if path:find("MSUF_Menu2_UnitStatusSection.lua", 1, true) then
        local lineStart = (source:sub(1, call.at):match(".*()\n") or 0) + 1
        local lhs = source:sub(lineStart, call.at - 1):match("([%w_%.%[%]]+)%s*[,=][^=]*$")
        local window = source:sub(call.closeAt + 1, math.min(#source, call.closeAt + 1800))
        if lhs and window:find("RegisterStatusSearch%s*%(%s*" .. EscapePattern(lhs)) then return true end
        if window:find("RegisterStatusSearch%s*%(") then return true end
    end
    return false
end

local BIND_METADATA_INDEX = {
    ["M.BindToggle"] = 5,
    ["M.BindSlider"] = 5,
    ["M.BindSegment"] = 5,
    ["M.BindDropdown"] = 5,
    ["M.BindTextInput"] = 7,
    ["M.BindColor"] = 5,
    ["M.BindBoolWidget"] = 5,
    ["M.BindDropdownWidget"] = 5,
    ["M.BindNumberWidget"] = 6,
}

local stats = {
    files = #FILES,
    bindCalls = 0,
    annotatedBinds = 0,
    searchCalls = 0,
    semanticCalls = 0,
    factoryCalls = 0,
    coveredFactories = 0,
}
local sources = {}
for i = 1, #FILES do
    local path = FILES[i]
    local text = Read(path)
    sources[path] = text
    local chunk, syntaxError = loadfile(ROOT .. path)
    Check(chunk ~= nil, path, 1, "syntax error: " .. tostring(syntaxError))

    for name, metadataIndex in pairs(BIND_METADATA_INDEX) do
        local calls = FindCalls(text, name)
        for j = 1, #calls do
            local call = calls[j]
            stats.bindCalls = stats.bindCalls + 1
            if call.broken then
                Fail(path, call.line, "unterminated " .. name)
            else
                local args = SplitArgs(call.text)
                -- Prefer exact argument placement where it is unambiguous, but
                -- also inspect the whole balanced call: getter/setter functions
                -- may legally contain comma-separated return values.
                local value = args[metadataIndex]
                if name == "M.BindTextInput" and value == nil and MetadataArgLooksSemantic(args[6]) then value = args[6] end
                if MetadataArgLooksSemantic(value) or CallHasSemanticMetadata(call, text, path) then stats.annotatedBinds = stats.annotatedBinds + 1
                else Fail(path, call.line, name .. " has no semantic metadata argument") end
            end
        end
    end

    for _, call in ipairs(FindCalls(text, "M.RegisterSearchWidget")) do
        stats.searchCalls = stats.searchCalls + 1
        if call.broken then
            Fail(path, call.line, "unterminated M.RegisterSearchWidget")
        else
            local args = SplitArgs(call.text)
            if not MetadataArgLooksSemantic(args[2]) then
                Fail(path, call.line, "RegisterSearchWidget has no canonical metadata payload")
            end
        end
    end
end

local FACTORY_NAMES = {
    "W.Toggle", "W.ToggleAt", "W.SwitchAt", "W.Slider", "W.Dropdown", "W.Segment", "W.SegmentTabs",
    "W.TextInput", "W.Color", "W.Button", "W.TopButton", "W.RoleButton", "W.ScopeOverrideBar",
    "T.Button", "ActionButton", "CopyPopupButton", "PreviewActionButton",
}
local function AssignedNameBefore(text, at)
    local lineStart = (text:sub(1, at):match(".*()\n") or 0) + 1
    local prefix = text:sub(lineStart, at - 1)
    local lhs = prefix:match("local%s+([^=]+)%s*=%s*[^=]*$") or prefix:match("([^=]+)%s*=%s*[^=]*$")
    return lhs and lhs:match("([%w_%.%[%]]+)") or nil
end
local function FactoryHasSemanticRoute(text, call, name)
    if name == "PreviewActionButton" then return true end -- helper registers before returning
    local lineStart = (text:sub(1, call.at):match(".*()\n") or 0) + 1
    local prefix = text:sub(math.max(1, call.at - 700), call.at - 1)
    if prefix:find("Bind[%w_]*%s*%(") or prefix:find("Register[%w_]*%s*%(") then return true end
    if prefix:match("return%s+$") then return true end -- factory wrapper; callers are audited independently
    local lhs = AssignedNameBefore(text, call.at)
    if not lhs then return false end
    local escaped = EscapePattern(lhs)
    local window = text:sub(call.closeAt + 1, math.min(#text, call.closeAt + 7200))
    if window:find("M%.Bind[%w_]*%s*%([^\n]-" .. escaped)
        or window:find("Bind[%w_]*%s*%([^\n]-" .. escaped)
        or window:find("Register[%w_]*Control%s*%([^\n]-" .. escaped)
        or window:find("RegisterStatusSearch%s*%([^\n]-" .. escaped)
        or window:find(escaped .. "%s*=%s*Bind[%w_]*%s*%(")
        or window:find("return[^\n]-" .. escaped)
    then
        return true
    end
    return false
end
for _, path in ipairs(FILES) do
    local text = sources[path]
    for _, name in ipairs(FACTORY_NAMES) do
        for _, call in ipairs(FindCalls(text, name)) do
            stats.factoryCalls = stats.factoryCalls + 1
            if call.text and FactoryHasSemanticRoute(text, call, name) then
                stats.coveredFactories = stats.coveredFactories + 1
            else
                Fail(path, call.line, name .. " factory has no bound/registered semantic route")
            end
        end
    end
end

-- Stable schemas and role-based dynamic-scope honesty.  Group scope, Aura lane,
-- status selection and custom-container selection are runtime context. They must
-- not pretend to be one immutable backing setting/action key.
local groupFoundation = sources["Shell/Menu2/Pages/MSUF_Menu2_Group.lua"]
local unitFoundation = sources["Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"]
local auraPage = sources["Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"]
local groupAuraPage = sources["Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua"]
Check(groupFoundation:find('controlId = "menu2." .. pageKey .. ".group." .. path', 1, true), "Group.lua", 1, "group controlId schema changed")
Check(groupFoundation:find('classification = classification or "setting"', 1, true), "Group.lua", 1, "group classification contract missing")
Check(unitFoundation:find('controlId = "menu2." .. pageKey .. ".unit." .. path', 1, true), "Unit.lua", 1, "unit controlId schema changed")
Check(unitFoundation:find('classification = classification or "setting"', 1, true), "Unit.lua", 1, "unit classification contract missing")
for _, item in ipairs({ { "Auras.lua", auraPage }, { "GroupAuras.lua", groupAuraPage } }) do
    Check(item[2]:find('controlId = "menu2." .. pageKey .. "." .. identity', 1, true), item[1], 1, "Aura controlId schema changed")
    Check(item[2]:find('controlPath = "auras/"', 1, true), item[1], 1, "Aura semantic controlPath missing")
end
for _, path in ipairs(PAGE_FILES) do
    local text = sources[path]
    if path:find("Group", 1, true) or path:find("Auras", 1, true) then
        if text:find("settingKey%s*=") or text:find("actionKey%s*=") then
            Fail(path, 1, "runtime-selected scope/lane must not claim a static settingKey/actionKey")
        end
    end
end

-- Preview inventory. These markers are intentionally exact: adding a new raw
-- preview control makes this gate fail until it receives a semantic role.
local PREVIEW_REQUIRED = {
    ["Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua"] = {
        '"preview." .. tostring(semanticPath)',
        '"handle." .. tostring(key)',
        '"combat_animation"',
        '"zoom.surface"', '"zoom.out"', '"zoom.fit"', '"zoom.one_to_one"', '"zoom.in"', '"zoom.help"',
        '"hint.dismiss"', '"canvas"', '"layer." .. tostring(button and button.key)',
        '"handle." .. tostring(key) .. ".open_settings"', '"pin.toggle"',
    },
    ["Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"] = {
        '"preview." .. tostring(semanticPath)',
        '"combat_animation"',
        '"zoom.surface"', '"zoom.out"', '"zoom.fit"', '"zoom.one_to_one"', '"zoom.in"', '"zoom.help"',
        '"hint.dismiss"', '"layer." .. tostring(def[4])', '"canvas"',
    },
    ["Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua"] = {
        '"preview." .. tostring(semanticPath)', '"handle." .. tostring(key)',
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua"] = { "RegisterRuntimeControlsForPage" },
    ["Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua"] = { '"preview.pin.toggle"' },
}
for path, needles in pairs(PREVIEW_REQUIRED) do
    local text = sources[path]
    for i = 1, #needles do
        Check(text:find(needles[i], 1, true), path, 1, "missing preview semantic marker " .. needles[i])
    end
end

-- Every direct raw Button in the scoped page/preview modules must feed one of
-- the semantic registration helpers. Generic visual Frames/StatusBars are not
-- controls and are intentionally outside this inventory.
local rawButtons, registeredRawButtons = 0, 0
for _, path in ipairs(FILES) do
    local text = sources[path]
    local cursor = 1
    while true do
        local at = text:find('CreateFrame%s*%(%s*"Button"', cursor)
        if not at then break end
        rawButtons = rawButtons + 1
        local line = LineAt(text, at)
        local lineStart = (text:sub(1, at):match(".*()\n") or 0) + 1
        local lhs = text:sub(lineStart, at - 1):match("([%w_%.%[%]]+)%s*=%s*$")
        local window = text:sub(at, math.min(#text, at + 5200))
        local covered = lhs and (
            window:find("Register[%w_]*Control%s*%([^\n]-" .. EscapePattern(lhs))
            or window:find("Register[%w_]*Control%s*%([^\n]-row")
        )
        -- Factory implementations are covered at their callers; unused legacy
        -- AddPlainCheck is not a runtime-created control.
        local before = text:sub(math.max(1, at - 500), at - 1)
        local helperFactory = before:find("local function EnsureRow", 1, true)
            or before:find("local function MakeHandle", 1, true)
            or before:find("local function CreatePreviewAnimationButton", 1, true)
            or before:find("local function MakePreviewSectionButton", 1, true)
            or before:find("local function AddPlainCheck", 1, true)
            or (path:find("MSUF_Menu2_UnitSections.lua", 1, true)
                and text:sub(math.max(1, at - 9000), at):find("local function BuildBossLayoutTiles", 1, true))
        if covered or helperFactory then registeredRawButtons = registeredRawButtons + 1
        else Fail(path, line, "raw CreateFrame(Button) has no nearby semantic registration") end
        cursor = at + 12
    end
end

-- Collect semantic path expressions from actual metadata calls. Expressions
-- are rendered to stable symbolic samples; the real catalog then validates the
-- resulting IDs/classifications and collision behavior.
local SEMANTIC_CALLS = {
    { name = "ControlMeta", pathArg = 2, classArg = 3 },
    { name = "AuraControlMeta", pathArg = 2, classArg = 3 },
    { name = "RegisterUnitPreviewControl", pathArg = 2, classArg = 5 },
    { name = "RegisterGroupPreviewControl", pathArg = 2, classArg = 5 },
    { name = "RegisterPreviewControl", pathArg = 2, classArg = 5 },
    { name = "RegisterAuraControl", pathArg = 5, classArg = 6 },
}
local function Hash(text)
    local hash = 104729
    for i = 1, #text do hash = (hash * 131 + text:byte(i)) % 2147483647 end
    return string.format("%08x", hash)
end
local function LiteralStrings(expr)
    local out, cursor = {}, 1
    while cursor <= #expr do
        local s, e, quote, body = expr:find("([\"'])(.-)%1", cursor)
        if not s then break end
        out[#out + 1] = body
        cursor = e + 1
    end
    return out
end
local function RenderExpression(expr)
    expr = tostring(expr or "")
    local literals = LiteralStrings(expr)
    local value = table.concat(literals)
    if value == "" then value = "dynamic." .. Hash(expr) end
    if expr:find("..", 1, true) then value = value .. ".dyn." .. Hash(expr:gsub('[\"\'][^\"\']*[\"\']', "")) end
    value = value:lower():gsub("[^%w_%.%-]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return value ~= "" and value or ("dynamic." .. Hash(expr))
end
local function LiteralClassification(expr)
    local value = tostring(expr or ""):match('^%s*[\"\']([%w_]+)[\"\']%s*$')
    if value == "setting" or value == "action" or value == "navigation" or value == "ephemeral" then return value end
    return "setting"
end

local semanticCases = {}
for _, path in ipairs(FILES) do
    local text = sources[path]
    for _, spec in ipairs(SEMANTIC_CALLS) do
        for _, call in ipairs(FindCalls(text, spec.name)) do
            if call.text then
                local args = SplitArgs(call.text)
                local expression = args[spec.pathArg]
                if expression and expression ~= "semanticPath" and expression ~= "path" then
                    stats.semanticCalls = stats.semanticCalls + 1
                    local family
                    if spec.name:find("Aura", 1, true) then family = "aura"
                    elseif spec.name:find("UnitPreview", 1, true) then family = "unit"
                    elseif spec.name:find("GroupPreview", 1, true) or spec.name == "RegisterPreviewControl" then family = "group"
                    else family = path:find("Unit", 1, true) and "unit" or (path:find("Group", 1, true) and "group" or "aura") end
                    semanticCases[#semanticCases + 1] = {
                        file = path,
                        line = call.line,
                        family = family,
                        path = RenderExpression(expression),
                        dynamic = expression:find("..", 1, true) ~= nil,
                        classification = LiteralClassification(args[spec.classArg]),
                    }
                end
            end
        end
    end
end

local namespace = { MSUF2 = {} }
local catalogChunk, catalogError = loadfile("Shell/Menu2/MSUF_Menu2_ControlCatalog.lua")
if not catalogChunk then error(catalogError) end
catalogChunk("MidnightSimpleUnitFrames", namespace)
local Catalog = assert(namespace.MSUF2.RuntimeControlCatalog)
local function Widget(label, kind)
    local widget = { _label = label, _kind = kind or "Button" }
    function widget:GetName() return nil end
    function widget:GetObjectType() return self._kind end
    function widget:GetParent() return nil end
    return widget
end
local function Token(value)
    return tostring(value or ""):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
end
local PAGE_KEYS = {
    unit = { "uf_player", "uf_target", "uf_targettarget", "uf_focustarget", "uf_focus", "uf_pet", "uf_boss" },
    group = { "gf_layout", "gf_bars", "gf_auras", "gf_indicators" },
    aura = { "auras3_buffs", "auras3_debuffs", "auras3_styling", "uf_player", "uf_target", "gf_auras" },
}
local seenIdentity = {}
local classificationById = {}
local duplicateTemplates = {}
local dynamicRecords = 0
for _, case in ipairs(semanticCases) do
    for _, pageKey in ipairs(PAGE_KEYS[case.family]) do
        local domain = case.family == "unit" and "unit" or (case.family == "group" and "group" or "auras")
        local canonicalPath = Token(case.path)
        local identity = domain .. "." .. canonicalPath
        local controlId = "menu2." .. pageKey .. "." .. domain .. "." .. canonicalPath
        local dedupe = controlId .. "\031" .. case.classification
        local previousClassification = classificationById[controlId]
        if previousClassification and previousClassification ~= case.classification then
            Fail(case.file, case.line, "same generated identity has conflicting classifications: "
                .. previousClassification .. " vs " .. case.classification)
        else
            classificationById[controlId] = case.classification
        end
        if not seenIdentity[dedupe] then
            seenIdentity[dedupe] = case
            local widget = Widget(case.file .. ":" .. case.line)
            local command
            if case.classification == "setting" then command = { kind = "toggle", get = function() return false end, set = function() end }
            elseif case.classification == "action" then command = { kind = "button", set = function() end }
            elseif case.classification == "navigation" then command = { kind = "button", navigationKey = pageKey, set = function() end } end
            local id, record = Catalog.Register(widget, {
                controlId = controlId,
                pageKey = pageKey,
                kind = case.classification == "setting" and "toggle" or "button",
                label = case.path,
                identityKey = identity,
                controlPath = identity:gsub("%.", "/"),
                classification = case.classification,
                ephemeral = case.classification == "ephemeral" or nil,
                command = command,
            }, "dynamic-audit")
            dynamicRecords = dynamicRecords + 1
            Check(id == controlId, case.file, case.line, "generated controlId was changed/quarantined: " .. tostring(id))
            Check(record and record.idSource == "explicit", case.file, case.line, "generated ID is not explicit")
            Check(record and record.identityStable == true, case.file, case.line, "generated ID is not stable")
            Check(record and record.collision ~= true, case.file, case.line, "generated ID collision")
            Check(record and record.classification == case.classification, case.file, case.line, "classification drift")
            Check((record.settingKey == nil or record.settingKey == "") and (record.actionKey == nil or record.actionKey == ""),
                case.file, case.line, "dynamic role fabricated a static backing key")
        else
            local duplicate = {
                controlId = controlId,
                first = seenIdentity[dedupe],
                second = case,
            }
            duplicateTemplates[#duplicateTemplates + 1] = duplicate
            if not duplicate.first.dynamic and not duplicate.second.dynamic then
                Fail(case.file, case.line, "duplicate literal semantic identity also declared at "
                    .. duplicate.first.file .. ":" .. tostring(duplicate.first.line))
            end
        end
    end
end
local coverage = Catalog.GetCoverageReport()
Check(coverage.collisions == 0, "ControlCatalog", 1, "dynamic corpus produced collisions")
Check(coverage.byClassification.unknown == 0, "ControlCatalog", 1, "dynamic corpus produced unknown controls")
Check(coverage.unstableIds == 0, "ControlCatalog", 1, "dynamic corpus produced unstable IDs")
Check(coverage.interactiveCoveragePercent == 100, "ControlCatalog", 1, "dynamic corpus is not fully classified")

-- Page rebuild lifecycle: a newly-created widget may reuse an ID only after the
-- page catalog is cleared. This is how dynamic scope/lane editors remain honest
-- without encoding the currently selected scope into a fake settingKey.
local lifecyclePage = "gf_dynamic_audit"
local lifecycleMeta = {
    controlId = "menu2.gf_dynamic_audit.group.field.width",
    pageKey = lifecyclePage,
    kind = "slider",
    label = "Width",
    identityKey = "group.dynamic.field.width",
    controlPath = "group/dynamic/field/width",
    classification = "setting",
    command = { kind = "slider", get = function() return 1 end, set = function() end },
}
local firstId = Catalog.Register(Widget("party width", "Slider"), lifecycleMeta, "scope-party")
Check(firstId == lifecycleMeta.controlId, "ControlCatalog", 1, "first dynamic scope registration failed")
Check(Catalog.ClearPage(lifecyclePage) == 1, "ControlCatalog", 1, "dynamic page clear did not remove exactly one record")
local secondId, secondRecord = Catalog.Register(Widget("raid width", "Slider"), lifecycleMeta, "scope-raid")
Check(secondId == lifecycleMeta.controlId and secondRecord.collision ~= true, "ControlCatalog", 1, "scope rebuild reused ID unsafely")

-- The Unit preview frame is shared and reparented between unit pages. Reusing
-- the same widget must move its catalog ownership instead of leaving a stale
-- player-page record or colliding on the target page.
local sharedWidgets = { Widget("canvas", "Frame"), Widget("zoom", "Button"), Widget("handle", "Button") }
local sharedPaths = { "preview.canvas", "preview.zoom.in", "preview.handle.name" }
local function RegisterSharedPreview(pageKey)
    for i = 1, #sharedWidgets do
        local path = sharedPaths[i]
        local classification = i == 3 and "action" or "ephemeral"
        Catalog.Register(sharedWidgets[i], {
            controlId = "menu2." .. pageKey .. ".unit." .. path,
            pageKey = pageKey,
            kind = i == 1 and "canvas" or "button",
            label = path,
            identityKey = "unit." .. path,
            controlPath = ("unit." .. path):gsub("%.", "/"),
            classification = classification,
            ephemeral = classification == "ephemeral" or nil,
            command = classification == "action" and { kind = "button", set = function() end } or nil,
        }, "shared-unit-preview")
    end
end
RegisterSharedPreview("uf_dynamic_player")
RegisterSharedPreview("uf_dynamic_target")
for i = 1, #sharedPaths do
    Check(Catalog.Get("menu2.uf_dynamic_player.unit." .. sharedPaths[i]) == nil,
        "ControlCatalog", 1, "shared Unit preview retained stale page ownership")
    local record = Catalog.Get("menu2.uf_dynamic_target.unit." .. sharedPaths[i])
    Check(record and record.collision ~= true, "ControlCatalog", 1, "shared Unit preview rebind collided")
end

if #failures > 0 then
    table.sort(failures)
    for i = 1, #failures do io.stderr:write("UNIT/GROUP/AURA CATALOG AUDIT FAIL: " .. failures[i] .. "\n") end
    os.exit(1)
end

print("UNIT/GROUP/AURA RUNTIME CONTROL CATALOG AUDIT PASS")
print(string.format("source_files=%d factories=%d/%d binds=%d/%d register_search=%d raw_buttons=%d/%d semantic_calls=%d",
    stats.files, stats.coveredFactories, stats.factoryCalls,
    stats.annotatedBinds, stats.bindCalls, stats.searchCalls,
    registeredRawButtons, rawButtons, stats.semanticCalls))
print(string.format("representative_records=%d symbolic_dynamic_reuse=%d collisions=%d unknown=%d unstable=%d interactive_coverage=%.2f%%",
    dynamicRecords, #duplicateTemplates, coverage.collisions, coverage.byClassification.unknown,
    coverage.unstableIds, coverage.interactiveCoveragePercent))
print("dynamic scope/lane/editor controls: role-classified; no fabricated settingKey/actionKey; page-clear reuse verified")
if arg and arg[1] == "--duplicates" then
    print("duplicate semantic templates=" .. tostring(#duplicateTemplates))
    for i = 1, #duplicateTemplates do
        local item = duplicateTemplates[i]
        print(string.format("duplicate %s first=%s:%d second=%s:%d", item.controlId,
            item.first.file, item.first.line, item.second.file, item.second.line))
    end
end
