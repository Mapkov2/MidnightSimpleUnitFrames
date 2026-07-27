-- Combined source/runtime gate for the Unit, Group, Aura, and preview portions
-- of the Menu2 runtime control catalog.
--
-- Usage from the repository root:
--   lua tools/assistant_control_catalog_unit_group_aura_audit.lua MidnightSimpleUnitFrames

local coreRoot = arg[1] or "MidnightSimpleUnitFrames"
local repositoryRoot = coreRoot:match("^(.*)[/\\]MidnightSimpleUnitFrames$") or "."
if repositoryRoot == "" then repositoryRoot = "." end
local addonRoot = repositoryRoot .. "/MidnightSimpleUnitFrames_Options"
local assistantRoot = repositoryRoot .. "/MidnightSimpleUnitFrames_Assistant"

local failures = {}
local function Fail(message) failures[#failures + 1] = tostring(message) end
local function Check(value, message) if not value then Fail(message) end end

local function Read(relative)
    local file, err = io.open(addonRoot .. "/" .. relative, "rb")
    if not file then error(err) end
    local content = file:read("*a")
    file:close()
    return content
end

local unitFiles = {
    "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitAlpha.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua",
}
local groupFiles = {
    "Shell/Menu2/Pages/MSUF_Menu2_Group.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua",
}
local auraFiles = { "Shell/Menu2/Pages/MSUF_Menu2_Auras.lua" }
local previewFiles = {
    "Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua",
}

local source = {}
for _, list in ipairs({ unitFiles, groupFiles, auraFiles, previewFiles }) do
    for i = 1, #list do source[list[i]] = Read(list[i]) end
end

local function RequireText(relative, needle, reason)
    Check(source[relative]:find(needle, 1, true) ~= nil, relative .. ": " .. (reason or ("missing " .. needle)))
end

-- Stable IDs must carry their owner explicitly. Ambient active/build keys are
-- deliberately not accepted as proof because the shared Unit preview is
-- reparented between cached pages.
for _, relative in ipairs({
    "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Group.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Auras.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua",
}) do
    RequireText(relative, "pageKey = pageKey", "ControlMeta does not declare explicit page ownership")
    RequireText(relative, "controlId = \"menu2.\"", "ControlMeta has no explicit stable ID")
    RequireText(relative, "identityKey =", "ControlMeta has no semantic identity")
    RequireText(relative, "controlPath =", "ControlMeta has no semantic path")
    if relative == "Shell/Menu2/Pages/MSUF_Menu2_Auras.lua" then
        RequireText(relative, 'meta.actionKey = navigationKey',
            "Aura controls cannot attach an explicit canonical action identity")
        RequireText(relative, '"reset_all_aura_style_overrides"',
            "Aura Style reset control lacks its exact Assistant action identity")
    elseif relative == "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua" then
        RequireText(relative, "local function UnitSettingMeta", "fixed Unit scopes have no exact setting metadata factory")
        RequireText(relative, "meta.settingKey = unit .. \".\" .. key", "Unit metadata factory does not preserve the exact DB scope/key")
    elseif relative == "Shell/Menu2/Pages/MSUF_Menu2_Group.lua"
        or relative == "Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua"
    then
        RequireText(relative, "assistantDisposition = \"dynamic\"",
            "selector-dependent Group controls have no reviewed dynamic disposition")
    end
end

local searchRelative = "Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua"
local searchSource = Read(searchRelative)
Check(searchSource:find("local previousPageKey = widget._msuf2SearchRegistryPage", 1, true),
    searchRelative .. ": widget page migration cleanup is missing")
Check(searchSource:find("SEARCH_STATE.registry[id] = nil", 1, true),
    searchRelative .. ": stale widget registry entry is not removed")

RequireText("Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", "box._msuf2PinnedPreviewPageKey = ctx and ctx.key",
    "shared Unit preview does not pin its owner page")
RequireText("Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", "preview.RegisterRuntimeControlsForPage(box, ctx and ctx.key)",
    "shared Unit preview is not re-registered after reparent")
RequireText("Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua", "local previewPageKey = box._msuf2PinnedPreviewPageKey or M2.activeKey",
    "late-created settings gear does not retain pinned page ownership")
RequireText("Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua", "}, previewPageKey)",
    "settings gear does not pass its pinned owner to registration")

local function BalancedCall(content, openAt)
    local depth, quote, escaped = 0, nil, false
    for i = openAt, #content do
        local ch = content:sub(i, i)
        if quote then
            if escaped then escaped = false
            elseif ch == "\\" then escaped = true
            elseif ch == quote then quote = nil end
        elseif ch == '"' or ch == "'" then
            quote = ch
        elseif ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then return content:sub(openAt, i) end
        end
    end
end

local bindingNames = {
    BindBoolWidget = true, BindNumberWidget = true, BindDropdownWidget = true,
    BindToggle = true, BindSlider = true, BindSegment = true,
    BindDropdown = true, BindTextInput = true, BindColor = true,
}
local bindCalls, annotatedBinds = 0, 0
for _, list in ipairs({ unitFiles, groupFiles, auraFiles }) do
    for _, relative in ipairs(list) do
        local content = source[relative]
        local cursor = 1
        while true do
            local startAt, openAt = content:find("M%.Bind[%a]+%s*%(", cursor)
            if not startAt then break end
            cursor = openAt + 1
            local name = content:sub(startAt, openAt):match("M%.(Bind[%a]+)")
            if bindingNames[name] then
                bindCalls = bindCalls + 1
                local call = BalancedCall(content, openAt)
                if not call then
                    Fail(relative .. ": unterminated " .. tostring(name) .. " call")
                elseif call:find("ControlMeta%(") or call:find("SettingMeta%(") or call:find("ReviewedMeta%(")
                    or call:find("FixedSettingMeta%(") or call:find("SelectedSlotMeta%(")
                    or call:find("AuraControlMeta%(") or call:find("StepMeta%(")
                    or call:find("ResolveGroupControlMeta%(") or call:find("SharedControlMeta%(")
                    or call:find("metadata", 1, true) or call:match("[,%(]%s*meta%s*[,)%s]")
                    or (relative == "Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua"
                        and content:sub(openAt + #call, openAt + #call + 900):find("RegisterStatusSearch%("))
                then
                    annotatedBinds = annotatedBinds + 1
                else
                    local line = 1 + select(2, content:sub(1, startAt):gsub("\n", ""))
                    Fail(string.format("%s:%d %s has no canonical catalog metadata", relative, line, name))
                end
            end
        end
    end
end

-- Raw buttons, view selectors, transient choice controls, and preview roles do
-- not all pass through a Bind API. These markers are the required semantic
-- registration points for those families.
local requiredMarkers = {
    ["Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua"] = {
        "RegisterControl(scopeBar, ctx, \"navigation.unit_page.selector\"", "RegisterControl(copy, ctx, \"copy.open\"",
        "RegisterControl(enableNow, ctx, \"basics.enable_now\"", "preview.RegisterRuntimeControlsForPage(box, ctx and ctx.key)",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua"] = {
        "RegisterControl(powerNoticeButton", "RegisterControl(castbarTabs", "RegisterControl(castbarNoticeButton",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua"] = {
        "RegisterControl(statusTabs", "RegisterStatusSearch(control", "RegisterStatusSearch(reset",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua"] = {
        "RegisterControl(tabs", "RegisterControl(powerManagedNoticeButton",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua"] = {
        "RegisterSharedControl(close", "RegisterSharedControl(btn", "RegisterSharedControl(cb",
        "RegisterSharedControl(allBtn", "RegisterSharedControl(noneBtn", "RegisterSharedControl(runBtn",
        "RegisterSharedControl(box", "RegisterSharedControl(pick", "RegisterSharedControl(clear", "RegisterSharedControl(frame",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_Group.lua"] = {
        "RegisterGroupControl(pageBar, ctx, \"navigation.section.selector\"", "RegisterGroupControl(scopeBar, ctx, \"scope.selector\"",
        "RegisterGroupControl(copy, ctx, \"copy.open\"", "RegisterGroupControl(btn, ctx, \"field.growth.option.",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua"] = {
        "W.AttachContextColorReferences(healthOpacityCard", "RegisterControl(generalNoticeButton",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua"] = { "RegisterControl(textTabs" },
    ["Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua"] = {
        "RegisterAuraControl(ctx, laneBar, \"Container\", \"segment\", \"group-workspace.container-selector\"",
        "RegisterAuraControl(ctx, toolBar, \"Edit\", \"segment\"",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua"] = {
        "W.AttachContextColorReferences(highlightCard", "RegisterControl(statusTabs", "RegisterControl(statusReset",
        "RegisterControl(advanced.reset", "RegisterControl(tile, self.ctx",
    },
    ["Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"] = {
        "RegisterAuraChoiceBar(ctx", "RegisterAuraControl(ctx, reset", "W.AttachContextColorReferences(section, references",
        "RegisterAuraTextAction(ctx, directAdd", "RegisterAuraTextAction(ctx, directRemove",
        "RegisterAuraControl(ctx, addSpell", "RegisterAuraControl(ctx, addSet", "RegisterAuraControl(ctx, row",
        "RegisterAuraControl(ctx, button, page[1]",
    },
    ["Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua"] = {
        "Register(box.zoomBar", "Register(box.canvas", "Register(box.animateCombatButton",
        "#(box.layerButtons or {})", "#(box.handles or {})", "handle._msuf2SettingsGear", "Register(box._msuf2PinButton",
    },
    ["Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"] = {
        "RegisterPreviewControl(box._zoomBar", "(registerControl or RegisterGroupPreviewControl)(btn, \"combat_animation\"",
        "RegisterPreviewControl(btn, \"layer.\"", "RegisterPreviewControl(mock, \"canvas\"",
    },
    ["Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua"] = { "RegisterPreviewControl(handle, \"handle.\"" },
    ["Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua"] = { "page.RegisterControl(box._msuf2PinButton" },
}
local rawMarkers = 0
for relative, needles in pairs(requiredMarkers) do
    local content = source[relative]
    for i = 1, #needles do
        rawMarkers = rawMarkers + 1
        Check(content:find(needles[i], 1, true), relative .. ": missing raw-control marker " .. needles[i])
    end
end

-- Exact drift sentinel for all currently in-scope interactive factory sites.
-- Any new raw factory forces this audit to be updated together with its Bind
-- metadata or direct semantic-registration marker.
local interactiveFactories = {
    Toggle = true, ToggleAt = true, SwitchAt = true, Slider = true, Dropdown = true,
    Color = true, TextInput = true, SegmentTabs = true, Button = true, TopButton = true, RoleButton = true,
}
local factorySites = 0
for _, list in ipairs({ unitFiles, groupFiles, auraFiles, previewFiles }) do
    for _, relative in ipairs(list) do
        local content = source[relative]
        for name in content:gmatch("W%.([%a]+)%s*%(") do
            if interactiveFactories[name] then factorySites = factorySites + 1 end
        end
        for _ in content:gmatch("T%.Button%s*%(") do factorySites = factorySites + 1 end
        for _ in content:gmatch("CreateFrame%s*%(%s*['\"]Button['\"]") do factorySites = factorySites + 1 end
    end
end
-- Current inventory includes the explicitly cataloged Group Indicator tile,
-- Group Preview button, Group Layout transparency/bar controls,
-- spell-indicator style controls, the four explicit compact-preview
-- controls added across Unit, Group, and Class Resources, and the mirrored
-- portrait cast-icon toggle on the Castbar Icon tab.
Check(factorySites == 204, string.format("interactive factory inventory drifted: expected 204, got %d", factorySites))

local function AddUnique(list, seen, value)
    value = tostring(value or "")
    if value ~= "" and not seen[value] then seen[value] = true; list[#list + 1] = value end
end

local function ExtractPipeKeys(content, startNeedle)
    local result, seen = {}, {}
    local startAt = content:find(startNeedle, 1, true)
    if not startAt then return result end
    local bodyStart = content:find("[[", startAt, true)
    local bodyEnd = bodyStart and content:find("]]", bodyStart + 2, true)
    if not (bodyStart and bodyEnd) then return result end
    local body = content:sub(bodyStart + 2, bodyEnd - 1)
    for line in body:gmatch("[^\r\n]+") do
        local key = line:match("^%s*([^|]+)")
        if key then AddUnique(result, seen, key:gsub("^%s+", ""):gsub("%s+$", "")) end
    end
    return result
end

local unitPreview = source["Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua"]
local unitAuraPreview = source["Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua"]
local unitSpecs = source["Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua"]
local unitLayers = ExtractPipeKeys(unitSpecs, "specs.PreviewLayers = LayerRows [[")
local unitStatus = ExtractPipeKeys(unitSpecs, "specs.StatusPreview = StatusRows [[")
local unitHandles, unitHandleSeen = {}, {}
for key in unitPreview:gmatch('MakeHandle%(%s*box%s*,%s*"([^"]+)"') do AddUnique(unitHandles, unitHandleSeen, key) end
for key in unitAuraPreview:gmatch('makeHandle%(%s*box%s*,%s*"([^"]+)"') do
    -- `"auraCustom" .. index` is a dynamic prefix, not a fourth custom
    -- Aura handle.  The three concrete handles are added just below.
    if key ~= "auraCustom" then AddUnique(unitHandles, unitHandleSeen, key) end
end
for i = 1, 3 do AddUnique(unitHandles, unitHandleSeen, "auraCustom" .. tostring(i)) end
for i = 1, #unitStatus do AddUnique(unitHandles, unitHandleSeen, unitStatus[i]) end
Check(#unitLayers == 12, string.format("Unit preview layer inventory drifted: expected 12, got %d", #unitLayers))
Check(#unitHandles == 39, string.format("Unit preview handle inventory drifted: expected 39, got %d", #unitHandles))

local groupNative = source["Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"]
local groupHandlesSource = source["Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua"]
local groupSpecs = Read("Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua")
local groupStatus = ExtractPipeKeys(groupSpecs, "GF_STATUS_ICON_SPECS = StatusIconSpecs [[")
local groupLayers = { "guides", "bounds", "buff", "trackedBuff", "debuff", "status", "si", "auraText", "text" }
for i = 1, #groupLayers do Check(groupNative:find('"' .. groupLayers[i] .. '"', 1, true), "missing Group preview layer " .. groupLayers[i]) end
local groupHandles, groupHandleSeen = {}, {}
for key in groupHandlesSource:gmatch('CreatePreviewHandle%(%s*"([^"]+)"') do
    -- `"status_" .. spec.value` is a dynamic prefix.  Count the concrete
    -- status-spec rows below instead of inventing a `status_` handle.
    if key ~= "status_" then AddUnique(groupHandles, groupHandleSeen, key) end
end
for i = 1, #groupStatus do AddUnique(groupHandles, groupHandleSeen, "status_" .. groupStatus[i]) end
Check(#groupHandles == 27, string.format("Group preview fixed-handle inventory drifted: expected 27, got %d", #groupHandles))
Check(groupHandlesSource:find("function box:EnsureSpellIndicatorHandle(item, index)", 1, true) ~= nil
    and groupHandlesSource:find('CreatePreviewHandle(key, "si"', 1, true) ~= nil,
    "Group preview dynamic spell-handle provider is missing")

local classPowerPreview = Read("Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua")
local classPowerHandles, classPowerHandleSeen = {}, {}
for key in classPowerPreview:gmatch('MakeHandle%(%s*box%s*,%s*"([^"]+)"') do
    AddUnique(classPowerHandles, classPowerHandleSeen, key)
end
Check(#classPowerHandles == 6,
    string.format("Class Resources preview handle inventory drifted: expected 6, got %d", #classPowerHandles))

local function ValueTextList(...)
    local values, out = { ... }, {}
    for i = 1, #values, 2 do out[#out + 1] = { value = values[i], text = values[i + 1] } end
    return out
end
local function SplitPlain(text, delimiter)
    local out, cursor = {}, 1
    text, delimiter = tostring(text or ""), tostring(delimiter or "|")
    while true do
        local at = text:find(delimiter, cursor, true)
        if not at then out[#out + 1] = text:sub(cursor); break end
        out[#out + 1] = text:sub(cursor, at - 1)
        cursor = at + #delimiter
    end
    return out
end
local function ValueTextPairs(text)
    local out = {}
    for _, row in ipairs(SplitPlain(text, "|")) do
        local at = row:find("=", 1, true)
        if at then out[#out + 1] = { value = row:sub(1, at - 1), text = row:sub(at + 1) } end
    end
    return out
end
local function KeyLabelRows(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local key, label = line:match("^%s*([^=]+)=(.*)$")
        if key then out[#out + 1] = { key = key, label = label } end
    end
    return out
end
local function ValueTextRows(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local value, label = line:match("^(.-)=(.*)$")
        if value then out[#out + 1] = { value = value, text = label } end
    end
    return out
end
local function PipeRows(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do out[#out + 1] = SplitPlain(line, "|") end
    return out
end

local function NewRuntime(loadSearch)
    local namespace = { MSUF2 = {} }
    namespace.ExportPublic = function(name, value) _G[name] = value; return value end
    local M = namespace.MSUF2
    M.ValueTextList, M.ValueTextPairs = ValueTextList, ValueTextPairs
    M.ValueTextRows, M.KeyLabelRows, M.PipeRows = ValueTextRows, KeyLabelRows, PipeRows
    M.WordList = function(words)
        local out = {}; for word in tostring(words or ""):gmatch("%S+") do out[#out + 1] = word end; return out
    end
    M.KeySetFromWords = function(words)
        local out = {}; for word in tostring(words or ""):gmatch("%S+") do out[word] = true end; return out
    end
    M.KeySet = function(...)
        local out = {}; for i = 1, select("#", ...) do out[select(i, ...)] = true end; return out
    end
    M.CopyFieldsFromSpecs = function() return {} end
    M.StatusBarTextureItems = function() return {} end
    M.DeepCopy = function(value) return value end
    M.Noop = function() end
    M.Tr = function(value) return value end
    M.Assign = function(target, values) for key, value in pairs(values or {}) do target[key] = value end; return target end
    M.Pick = function(values, names)
        local out = {}; values = values or {}
        for name in tostring(names or ""):gmatch("%S+") do out[#out + 1] = values[name] end
        return (unpack or table.unpack)(out)
    end
    M.PickDefaults = M.Pick
    M.GROUP_SPEC_TABLE_KEYS = "SCOPE_VALUES GROWTH_VALUES BLIZZARD_FALLBACK_VALUES HEALTH_MODES TEXT_MODES DELIMITER_VALUES ANCHORS AURA_ANCHORS SORT_MODES GF_BAR_MODES GF_ANCHOR_TO GF_ANCHOR_POINTS STATUS_ICON_ANCHORS GF_STATUS_ICON_SPECS GF_STATUS_ICON_VALUES PLACED_INDICATOR_TYPES FRAME_EFFECT_TYPES SPELL_GROWTH_VALUES CI_SLOT_VALUES CI_SLOT_DEFAULTS DISPEL_OVERLAY_STYLES DEBUFF_STRIPE_EDGES"
    M.Widgets, M.Theme, M.ControlGates, M.UnitSectionsShared = {}, {}, {}, {}
    M.ApplyService = { CallGlobal = function() end, SafeInvoke = function(fn, ...) return pcall(fn, ...) end }
    M.GetGeneralDB = function() return {} end
    M.pages, M.navItems = {}, {}
    _G.C_Timer = _G.C_Timer or { After = function() end, NewTimer = function() return { Cancel = function() end } end }
    _G.MSUF_FRAME_STRATA_RANK = _G.MSUF_FRAME_STRATA_RANK or { AUTO = true }

    assert(loadfile(addonRoot .. "/Shell/Menu2/MSUF_Menu2_ControlCatalog.lua"))("MidnightSimpleUnitFrames", namespace)
    if loadSearch then
        M.Search = { Text = setmetatable({ KEYWORDS = {} }, {
            __index = function() return function(value) return tostring(value or "") end end,
        }) }
        M.SearchData = setmetatable({ BuildFAQ = function() return {} end, EASTER_EGGS = {} }, {
            __index = function() return {} end,
        })
        assert(loadfile(addonRoot .. "/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua"))("MidnightSimpleUnitFrames", namespace)
    end
    assert(loadfile(addonRoot .. "/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(addonRoot .. "/Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(addonRoot .. "/Shell/Menu2/Pages/MSUF_Menu2_Group.lua"))("MidnightSimpleUnitFrames", namespace)
    return namespace, M, M.RuntimeControlCatalog
end

local function Widget(name, kind)
    local widget = { _name = name, _kind = kind or "Button" }
    function widget:GetName() return self._name end
    function widget:GetObjectType() return self._kind end
    function widget:GetParent() return nil end
    return widget
end

local runtimeNS, runtimeM, catalog = NewRuntime(false)

-- Dynamic Group spell selectors are natural-language ordered lists. Their
-- order must not inherit Lua pairs() iteration, and empty-state rows are UI
-- explanations rather than executable choices.
local groupConfs = {}
runtimeNS.GF = {
    SpellIndicators = {
        SpecInfo = {
            zulu = { display = "Zulu" },
            alpha = { display = "Alpha" },
        },
    },
    GetConf = function(kind)
        groupConfs[kind] = groupConfs[kind] or { spellIndicators = { spec = "auto", specs = {} } }
        return groupConfs[kind]
    end,
}
local orderedSpecs = runtimeM.GroupPage.SpellSpecValues()
Check(orderedSpecs[1].value == "auto" and orderedSpecs[2].value == "multi"
    and orderedSpecs[3].value == "alpha" and orderedSpecs[4].value == "zulu",
    "Group spell spec provider is not deterministic")
runtimeNS.GF.SpellIndicators.SpecInfo = {}
local emptySpecs = runtimeM.GroupPage.SpellTrackedSpecValues()
Check(#emptySpecs == 1 and emptySpecs[1].disabled == true,
    "Group empty spec placeholder is selectable")
local emptySpells = runtimeM.GroupPage.SpellAuraValues("party")
Check(#emptySpells == 1 and emptySpells[1].disabled == true,
    "Group empty spell placeholder is selectable")

local generated = 0
local function RegisterGenerated(meta, path, classification, navigationKey)
    classification = classification or "ephemeral"
    meta.label = path
    meta.kind = classification == "setting" and "slider" or "button"
    if classification == "setting" then
        meta.settingKey = meta.settingKey or table.concat({ "audit", tostring(meta.pageKey), tostring(path) }, ".")
        meta.assistantDisposition, meta.assistantDispositionReason = nil, nil
        meta.command = { kind = "slider", get = function() return 1 end, set = function() end, min = 0, max = 10, step = 1 }
    elseif classification == "navigation" then
        meta.navigationKey = navigationKey or meta.pageKey
    elseif classification == "action" then
        -- Runtime actions always need a directly executable command in V2;
        -- actionKey remains semantic identity, not a dependency on V1.
        meta.command = { kind = "button", set = function() return true end }
        if meta.actionKey ~= nil then
            Check(type(meta.actionKey) == "string" and meta.actionKey ~= "", meta.controlId .. " has an invalid semantic actionKey")
        else
            meta.assistantDisposition = "dynamic"
            meta.assistantDispositionReason = "Synthetic audit action targets the currently selected Unit or Group scope."
        end
    end
    local id, record = catalog.Register(Widget(meta.controlId, meta.kind), meta, "unit-group-aura-gate")
    Check(id == meta.controlId, "explicit control ID changed: " .. tostring(meta.controlId))
    Check(record and record.pageKey == meta.pageKey, tostring(meta.controlId) .. " has wrong page ownership")
    Check(record and record.identityStable == true, tostring(meta.controlId) .. " is not stable")
    generated = generated + 1
end

local unitPages = { "uf_player", "uf_target", "uf_targettarget", "uf_focustarget", "uf_focus", "uf_pet", "uf_boss" }
local unitBaseRoles = {
    "preview.zoom.surface", "preview.zoom.out", "preview.zoom.fit", "preview.zoom.one_to_one", "preview.zoom.in", "preview.zoom.help",
    "preview.hint.dismiss", "preview.canvas", "preview.combat_animation", "preview.pin.toggle",
}
for _, pageKey in ipairs(unitPages) do
    local ctx = { key = pageKey }
    RegisterGenerated(runtimeM.UnitPage.ControlMeta(ctx, "basics.enabled", "setting"), "basics.enabled", "setting")
    local enableNowMeta = runtimeM.UnitPage.ControlMeta(ctx, "basics.enable_now", "action")
    Check(enableNowMeta.actionKey == nil, pageKey .. ": dynamic Unit action claimed a static actionKey")
    RegisterGenerated(enableNowMeta, "basics.enable_now", "action")
    RegisterGenerated(runtimeM.UnitPage.ControlMeta(ctx, "navigation.unit_page.player", "navigation"), "navigation.unit_page.player", "navigation", "uf_player")
    for i = 1, #unitBaseRoles do
        RegisterGenerated(runtimeM.UnitPage.ControlMeta(ctx, unitBaseRoles[i], "ephemeral"), unitBaseRoles[i], "ephemeral")
    end
    for i = 1, #unitLayers do
        local path = "preview.layer." .. unitLayers[i]
        RegisterGenerated(runtimeM.UnitPage.ControlMeta(ctx, path, "ephemeral"), path, "ephemeral")
    end
    for i = 1, #unitHandles do
        local path = "preview.handle." .. unitHandles[i]
        local handleMeta = runtimeM.UnitPage.ControlMeta(ctx, path, "ephemeral")
        Check(handleMeta.actionKey == nil, pageKey .. ": Unit preview handle claimed a static actionKey")
        RegisterGenerated(handleMeta, path, "ephemeral")
        local gearPath = path .. ".open_settings"
        RegisterGenerated(runtimeM.UnitPage.ControlMeta(ctx, gearPath, "navigation"), gearPath, "navigation", pageKey)
    end
end

local groupPages = { "gf_layout", "gf_bars", "gf_auras", "gf_indicators", "gf_priority" }
local groupBaseRoles = {
    "preview.combat_animation", "preview.zoom.surface", "preview.zoom.out", "preview.zoom.fit", "preview.zoom.one_to_one",
    "preview.zoom.in", "preview.zoom.help", "preview.hint.dismiss", "preview.canvas", "preview.pin.toggle",
}
for _, pageKey in ipairs(groupPages) do
    local ctx = { key = pageKey }
    RegisterGenerated(runtimeM.GroupPage.ControlMeta(ctx, "field.enabled", "setting"), "field.enabled", "setting")
    local enableNowMeta = runtimeM.GroupPage.ControlMeta(ctx, "scope.enable_now", "action")
    Check(enableNowMeta.actionKey == nil, pageKey .. ": dynamic Group action claimed a static actionKey")
    RegisterGenerated(enableNowMeta, "scope.enable_now", "action")
    RegisterGenerated(runtimeM.GroupPage.ControlMeta(ctx, "navigation.section.layout", "navigation"), "navigation.section.layout", "navigation", "gf_layout")
    for i = 1, #groupBaseRoles do
        RegisterGenerated(runtimeM.GroupPage.ControlMeta(ctx, groupBaseRoles[i], "ephemeral"), groupBaseRoles[i], "ephemeral")
    end
    for i = 1, #groupLayers do
        local path = "preview.layer." .. groupLayers[i]
        RegisterGenerated(runtimeM.GroupPage.ControlMeta(ctx, path, "ephemeral"), path, "ephemeral")
    end
    for i = 1, #groupHandles do
        local path = "preview.handle." .. groupHandles[i]
        local handleMeta = runtimeM.GroupPage.ControlMeta(ctx, path, "ephemeral")
        Check(handleMeta.actionKey == nil, pageKey .. ": Group preview handle claimed a static actionKey")
        RegisterGenerated(handleMeta, path, "ephemeral")
    end
end

local function AuraMeta(pageKey, path, classification)
    path = tostring(path or "control"):lower():gsub("[^%w%._/-]+", "-")
    path = path:gsub("/", "."):gsub("^%.", ""):gsub("%.$", "")
    pageKey = tostring(pageKey or "auras"):lower():gsub("[^%w_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    local identity = "auras." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. "." .. identity,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = "auras/" .. path:gsub("%.", "/"),
        classification = classification or "setting",
        ephemeral = classification == "ephemeral" or nil,
    }
    if meta.classification == "action" then meta.actionKey = identity end
    return meta
end
local auraPages = { "gf_auras", "auras3_buffs", "auras3_debuffs", "auras3_custom", "auras3_styling", "auras3_filters" }
local auraPaths = {
    { "style.scope.override", "setting" }, { "style.scope.reset-overrides", "action" },
    { "style.lane.buff.layout.icon-size", "setting" }, { "style.lane.debuff.stack-anchor", "setting" },
    { "group-style.lane.buff.cooldown-swipe-direction", "setting" },
    { "group-blacklist.lane.buff.manual-input", "ephemeral" }, { "group-blacklist.lane.buff.add", "action" },
    { "group-blacklist.lane.debuff.preset-selection", "ephemeral" }, { "group-blacklist.lane.debuff.add-preset-spell", "action" },
    { "unit-workspace.lane.buff.filters.enabled", "setting" }, { "unit-workspace.lane.debuff.blacklist.add-preset-spell", "action" },
    { "custom-container.whitelist.input", "ephemeral" }, { "custom-container.whitelist.add", "action" },
    { "custom-container.layout.anchor", "setting" }, { "custom-container.appearance.duration-display", "setting" },
    { "custom-container.effect.color", "setting" }, { "custom-container.setup.reset", "action" },
    { "moved-page.open.auras3-styling", "navigation", "auras3_styling" },
    { "group-workspace.lane.buff.layout.anchor", "setting" },
}
for _, pageKey in ipairs(auraPages) do
    for i = 1, #auraPaths do
        local row = auraPaths[i]
        RegisterGenerated(AuraMeta(pageKey, row[1], row[2]), row[1], row[2], row[3])
    end
end

local coverage = catalog.GetCoverageReport()
local validation = catalog.ValidateAll()
Check(coverage.total == generated, string.format("generated catalog lost records: %d/%d", coverage.total, generated))
Check(coverage.explicitIds == generated, "not every generated control has an explicit ID")
Check(coverage.unstableIds == 0, "generated catalog contains unstable IDs")
Check(coverage.collisions == 0, "generated catalog contains collisions")
Check(coverage.byClassification.unknown == 0, "generated catalog contains unknown semantics")
Check(coverage.assistantContractComplete == true, "generated Unit/Group/Aura Assistant contract is not complete")
Check(coverage.assistantRegistryCrosswalkComplete == true, "generated Unit/Group/Aura Registry crosswalk is not complete")
Check(coverage.invalidCapabilityCount == 0, "generated catalog contains invalid command capabilities")
Check(validation.valid == true and #validation.errors == 0, "generated catalog failed schema validation")
Check(#validation.warnings == 0, "generated catalog contains semantic validation warnings")

-- Natural-language coverage belongs to the restored V1 registry/parser gate.
-- The 5,017-case AssistantTraining parity oracle exercises every registered
-- setting plus every action; this audit remains the authoritative inventory
-- and ownership gate for the real RuntimeControlCatalog records themselves.

-- Exercise the actual Search registry and actual Unit metadata helper with an
-- intentionally wrong ambient active/build key. The shared widget must have
-- exactly one live search record and one catalog owner after each reparent.
local _, reparentM, reparentCatalog = NewRuntime(true)
reparentM.activeKey = "ambient_wrong_page"
reparentM._msuf2SearchBuildKey = "ambient_wrong_build"
local sharedWidget = Widget("SharedUnitPreviewPin", "Button")
sharedWidget._msuf2SearchText = "Pin Preview"
local previousControlId, previousRegistryId
for i = 1, #unitPages do
    local pageKey = unitPages[i]
    local meta = reparentM.UnitPage.ControlMeta({ key = pageKey }, "preview.pin.toggle", "ephemeral")
    meta.label, meta.kind = "Pin Preview", "button"
    reparentM.RegisterSearchWidget(sharedWidget, meta)
    local record = reparentCatalog.GetForWidget(sharedWidget)
    Check(record and record.controlId == meta.controlId, pageKey .. ": reparent control ID mismatch")
    Check(record and record.pageKey == pageKey, pageKey .. ": reparent owner followed ambient state")
    Check(sharedWidget._msuf2SearchRegistryPage == pageKey, pageKey .. ": search owner is stale")
    if previousControlId then Check(reparentCatalog.Get(previousControlId) == nil, pageKey .. ": prior catalog owner survived reparent") end
    if previousRegistryId then Check(reparentM.searchRegistry[previousRegistryId] == nil, pageKey .. ": prior search record survived reparent") end
    local liveRegistry = 0
    for _ in pairs(reparentM.searchRegistry or {}) do liveRegistry = liveRegistry + 1 end
    Check(liveRegistry == 1, pageKey .. ": shared widget has duplicate search records")
    local report = reparentCatalog.GetCoverageReport()
    Check(report.total == 1 and report.byPage[pageKey] and report.byPage[pageKey].total == 1,
        pageKey .. ": catalog page ownership is not singular")
    previousControlId = meta.controlId
    previousRegistryId = sharedWidget._msuf2SearchRegistryId
end

if #failures > 0 then
    for i = 1, #failures do io.stderr:write("UNIT/GROUP/AURA CATALOG AUDIT FAIL: " .. failures[i] .. "\n") end
    os.exit(1)
end

print("UNIT/GROUP/AURA CONTROL CATALOG SOURCE+RUNTIME AUDIT PASS")
print(string.format("Source: %d/%d annotated Bind calls; %d interactive factories; %d raw-control/preview markers",
    annotatedBinds, bindCalls, factorySites, rawMarkers))
print(string.format("Runtime: %d canonical controls; explicit=%d unstable=%d unknown=%d collisions=%d",
    coverage.total, coverage.explicitIds, coverage.unstableIds, coverage.byClassification.unknown, coverage.collisions))
print(string.format("Classification: settings=%d actions=%d navigation=%d ephemeral=%d",
    coverage.byClassification.setting, coverage.byClassification.action,
    coverage.byClassification.navigation, coverage.byClassification.ephemeral))
print(string.format("Preview inventory: Unit layers=%d handles=%d; Group layers=%d fixed handles=%d+N; Class Resources handles=%d",
    #unitLayers, #unitHandles, #groupLayers, #groupHandles, #classPowerHandles))
print(string.format("Unit preview reparent: %d pages; singular catalog/search ownership preserved", #unitPages))
