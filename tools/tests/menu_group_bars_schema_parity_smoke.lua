-- Actual-parent replay of every GroupBars input and its retained native owners.
-- Offline geometry/history/combat checks do not establish client rendering or taint.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua"
local parentBlob = "1e684939c01c1f30e2184f784afea7826ddcb2e6"
local mode = arg[4] or "full"
assert(mode == "full" or mode == "push" or mode == "narrow" or mode == "contracts", "unknown parity tier")
local narrow = mode == "narrow"
local sourceOverride = arg[3] ~= "-" and arg[3] or nil
local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root .. '" show ' .. parentBlob, "r"))
local original = pipe:read("*a")
assert(pipe:close(), "actual parent blob read failed")
assert(original:find("local function BuildGFValueTextTab", 1, true), "actual parent page unavailable")
local scratch = os.tmpname()
local file = assert(io.open(scratch, "wb"))
file:write(original)
file:close()
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    if type(value) == "function" then return "<function>" end
    if type(value) == "string" then return "string:" .. value:gsub("table: %x+", "table:<address>") end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget:" .. tostring(ids[value] or "external") end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key, ids) .. "=" .. Encode(value[key], ids, seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local SECTION_IDS = { gf_bars = { "dispel", "dispelSymbol", "dstripe" }, gf_layout = { "power", "text", "range" } }
-- Reviewed declaration contract: existing133 identities plus the lead domain/card-key fixes.
local DECLARATIONS = {}
for contract, names in pairs({
    ["gf_bars|button|group|contextColors"] = "menu2.gf_bars.section.dispel.expanded.colors stripeCard.colors",
    ["gf_bars|card|group|presentation"] = "dispelCard dispelSymbolCard stripeCard",
    ["gf_bars|dropdown|group|visual"] = "menu2.gf_bars.group.field.debuffstripeedge menu2.gf_bars.group.field.dispeloverlaystyle menu2.gf_bars.group.field.dispeloverlaytrigger menu2.gf_bars.group.field.dispelsymbolanchor menu2.gf_bars.group.field.dispelsymbolgrowth menu2.gf_bars.group.field.dispelsymbolmode menu2.gf_bars.group.field.dispelsymbolstyle menu2.gf_bars.group.field.dispelsymboltrigger",
    ["gf_bars|slider|group|visual"] = "menu2.gf_bars.group.field.debuffstripeheight menu2.gf_bars.group.field.dispeloverlayalpha menu2.gf_bars.group.field.dispeloverlaylayer menu2.gf_bars.group.field.dispelsymbolalpha menu2.gf_bars.group.field.dispelsymbollayer menu2.gf_bars.group.field.dispelsymbolsize menu2.gf_bars.group.field.dispelsymbolspacing",
    ["gf_bars|text|group|presentation"] = "stripeHint",
    ["gf_bars|toggle|group|preview"] = "menu2.gf_bars.group.field.dispeloverlaypreview",
    ["gf_bars|toggle|group|sectionNavigation"] = "menu2.gf_bars.section.dispel.expanded menu2.gf_bars.section.dispelsymbol.expanded menu2.gf_bars.section.dstripe.expanded",
    ["gf_bars|toggle|group|visual"] = "menu2.gf_bars.group.field.debuffstripeenabled menu2.gf_bars.group.field.dispeloverlayenabled menu2.gf_bars.group.field.dispeloverlayonhealth menu2.gf_bars.group.field.dispelsymbolenabled",
    ["gf_layout|button|group|contextColors"] = "nameContent.colors powerBorderCard.colors powerMain.colors text.hp.content.colors text.power.content.colors",
    ["gf_layout|card|group|presentation"] = "nameAppearance nameContent namePosition powerBorderCard powerDetached powerMain powerRoles rangeAlpha rangeEffect text.hp.content text.hp.position text.power.content text.power.position textLayers",
    ["gf_layout|dropdown|group|font"] = "menu2.gf_layout.group.field.nameanchor",
    ["gf_layout|dropdown|group|visual"] = "menu2.gf_layout.group.field.powertextdelimiter menu2.gf_layout.group.field.textdelimiter menu2.gf_layout.group.text.hp.slot.mode menu2.gf_layout.group.text.power.slot.mode",
    ["gf_layout|preview|group|preview"] = "nameContent.preview text.hp.content.preview text.power.content.preview",
    ["gf_layout|segment|group|menuState"] = "menu2.gf_layout.group.text.hp.slot_selector menu2.gf_layout.group.text.power.slot_selector menu2.gf_layout.group.text.workspace_tab",
    ["gf_layout|segment|group|visual"] = "menu2.gf_layout.group.field.rangefadelayermode menu2.gf_layout.group.text.hp.slot.absorb",
    ["gf_layout|slider|group|color"] = "menu2.gf_layout.group.field.powerbarborderthickness",
    ["gf_layout|slider|group|font"] = "menu2.gf_layout.group.field.namefontsize menu2.gf_layout.group.field.nametextlayer menu2.gf_layout.group.field.powertextlayer menu2.gf_layout.group.field.textlayer menu2.gf_layout.group.text.hp.slot.size menu2.gf_layout.group.text.power.slot.size",
    ["gf_layout|slider|group|geometry"] = "menu2.gf_layout.group.field.detachedpowerbarframeleveloffset menu2.gf_layout.group.field.detachedpowerbarheight menu2.gf_layout.group.field.detachedpowerbarwidth menu2.gf_layout.group.field.powerheight",
    ["gf_layout|slider|group|visual"] = "menu2.gf_layout.group.field.offlinealpha menu2.gf_layout.group.field.rangefadealpha",
    ["gf_layout|text|group|presentation"] = "offlineHint powerHint text.hp.formatting text.power.formatting",
    ["gf_layout|toggle|group|color"] = "menu2.gf_layout.group.field.powerbarborderenabled",
    ["gf_layout|toggle|group|font"] = "menu2.gf_layout.group.field.hpfullvalueshort menu2.gf_layout.group.field.showhptext menu2.gf_layout.group.field.showname",
    ["gf_layout|toggle|group|geometry"] = "menu2.gf_layout.group.field.detachedpowerbartextonbar menu2.gf_layout.group.field.embedpowerbarintohealth menu2.gf_layout.group.field.powerbardetached menu2.gf_layout.group.field.powerbarenabled",
    ["gf_layout|toggle|group|menuState"] = "menu2.gf_layout.group.text.hp.move_together menu2.gf_layout.group.text.power.move_together",
    ["gf_layout|toggle|group|sectionNavigation"] = "menu2.gf_layout.section.power.expanded menu2.gf_layout.section.range.expanded menu2.gf_layout.section.text.expanded",
    ["gf_layout|toggle|group|visual"] = "menu2.gf_layout.group.field.healthtextdecimals menu2.gf_layout.group.field.hidenameondeadoffline menu2.gf_layout.group.field.hptextreverse menu2.gf_layout.group.field.offlinefadeenabled menu2.gf_layout.group.field.powerchunkedfill menu2.gf_layout.group.field.powershowdamager menu2.gf_layout.group.field.powershowhealer menu2.gf_layout.group.field.powershowtank menu2.gf_layout.group.field.powersmoothfill menu2.gf_layout.group.field.rangefadeenabled menu2.gf_layout.group.text.hp.slot.hide_percent menu2.gf_layout.group.text.power.show menu2.gf_layout.group.text.power.slot.hide_percent",
}) do
    local page, kind, scope, domain = contract:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
    DECLARATIONS[page] = DECLARATIONS[page] or {}
    for id in names:gmatch("%S+") do DECLARATIONS[page][id] = { kind, scope, domain } end
end
local RAW_NUMBER_CASES = {
    dispeloverlaylayer = { key = "dispelOverlayLayer", value = 2.25 },
    dispelsymbollayer = { key = "dispelSymbolLayer", value = 7.75 },
    dispelsymbolspacing = { key = "dispelSymbolSpacing", value = 3.5 },
}
-- Keys are pinned independently of the candidate schema so a wrong binding cannot
-- select its own test fixture. Menu-only state and the runtime preview have no DB key.
local NIL_FIELDS = {}
for key in ([[
    debuffStripeEdge dispelOverlayStyle dispelOverlayTrigger dispelSymbolAnchor dispelSymbolGrowth
    dispelSymbolMode dispelSymbolStyle dispelSymbolTrigger debuffStripeHeight dispelOverlayAlpha
    dispelOverlayLayer dispelSymbolAlpha dispelSymbolLayer dispelSymbolSize dispelSymbolSpacing
    debuffStripeEnabled dispelOverlayEnabled dispelOverlayOnHealth dispelSymbolEnabled nameAnchor
    powerTextDelimiter textDelimiter powerBarBorderThickness nameFontSize nameTextLayer powerTextLayer textLayer
    detachedPowerBarFrameLevelOffset detachedPowerBarHeight detachedPowerBarWidth powerHeight offlineAlpha rangeFadeAlpha
    powerBarBorderEnabled hpFullValueShort showHPText showName detachedPowerBarTextOnBar embedPowerBarIntoHealth
    powerBarDetached powerBarEnabled healthTextDecimals hideNameOnDeadOffline hpTextReverse offlineFadeEnabled
    powerChunkedFill powerShowDamager powerShowHealer powerShowTank powerSmoothFill rangeFadeEnabled rangeFadeLayerMode
]]):gmatch("%S+") do NIL_FIELDS[key:lower()] = key end
local function MissingKeys(w)
    local id = w._msuf2RuntimeControlRecord.controlId
    local field = id:match("%.field%.([^%.]+)$")
    if field == "dispeloverlaypreview" or id:find(".section.", 1, true)
        or id:find(".text.workspace_tab", 1, true) or id:find(".slot_selector", 1, true)
        or id:find(".move_together", 1, true) then return nil end
    if field then
        local key = assert(NIL_FIELDS[field], "missing nil-key field contract: " .. id)
        return { key }
    end
    if id:find(".text.power.show", 1, true) then return { "showPowerText", "showPower" } end
    local kind, role = id:match("%.text%.([^%.]+)%.slot%.([^%.]+)$")
    assert(kind == "hp" or kind == "power", "missing nil-key control contract: " .. id)
    local prefix = kind == "hp" and "hpTextCenter" or "powerTextCenter"
    if role == "mode" then return { kind == "hp" and "textCenter" or "powerTextCenter" } end
    if role == "size" then return { prefix .. "FontSize" } end
    if role == "hide_percent" then return { prefix .. "HidePercentSymbol" } end
    if role == "absorb" and kind == "hp" then return { prefix .. "AbsorbIcon" } end
    error("missing nil-key slot contract: " .. id)
end
local function Replay(source, candidate)
    local rows, ids, calls, refreshes, tips, previews = {}, {}, {}, 0, {}, {}
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                if source and path:sub(-#target) == target then path = source end
                return load(self, path, ...)
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    -- The actual parent page predates the namespace-only exports and reads them as globals. Its sandbox
    -- answers those reads from the live namespace registry, so both pages observe the same client.
    local meta = assert(getmetatable(env), "the client sandbox lost its global fallback")
    local fallback, registry = meta.__index, core.PublicGlobals
    meta.__index = function(table_, key)
        local published = registry[key]
        if published ~= nil then return published end
        if type(fallback) == "function" then return fallback(table_, key) end
        if fallback then return fallback[key] end
    end
    local GP, F = M.GroupPage, core.ProfileFields
    -- Observe the real shared factory's exact native returns, without replacing its widgets.
    local nativeTextPreviews, sharedPreviewText = {}, M.UnitSectionsShared.PreviewText
    M.UnitSectionsShared.PreviewText = function(parent, ...)
        local label, value = sharedPreviewText(parent, ...)
        nativeTextPreviews[#nativeTextPreviews + 1] = { parent = parent, label = label, value = value }
        return label, value
    end
    if narrow then
        local builder = M.Widgets.PageBuilder
        M.Widgets.PageBuilder = function(ctx, ...) ctx.width = 400 return builder(ctx, ...) end
    end
    local previewHooks, createToggle = {}, M.Widgets.ToggleAt
    M.Widgets.ToggleAt = function(parent, label, ...)
        local widget = createToggle(parent, label, ...)
        if label == "Runtime Preview: live GroupFrames" then
            local hook = widget.HookScript
            widget.HookScript = function(self, event, fn)
                previewHooks[#previewHooks + 1] = event
                return hook(self, event, fn)
            end
        end
        return widget
    end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    env.MSUF_SetDispelOverlayPreview = function(on, scope)
        core.ExportPublic("MSUF_DispelOverlayPreviewMode", on == true)
        previews[#previews + 1] = { on, scope }
    end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Diff(a, b, path, out)
        path, out = path or "", out or {}
        if type(a) == "table" and type(b) == "table" then
            local keys = {}
            for key in pairs(a) do keys[key] = true end
            for key in pairs(b) do keys[key] = true end
            for key in pairs(keys) do Diff(a[key], b[key], path .. "." .. tostring(key), out) end
        elseif Encode(a, ids) ~= Encode(b, ids) then out[path] = { Encode(a, ids), Encode(b, ids) } end
        return out
    end
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function Input(w, value)
        local command = Command(w)
        if command and command.kind == "toggle" then
            w:SetChecked(value)
            w:Click("LeftButton")
        elseif w.buttons then
            local found = false
            for _, button in ipairs(w.buttons) do
                if button._msuf2Value == value then button:Click("LeftButton") found = true break end
            end
            assert(found, "native segment choice missing: " .. tostring(value))
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        else
            assert(command and command.kind == "slider", "unsupported real input")
            World.FireScript(w, "OnMouseDown", "LeftButton")
            -- Cursor drags snap the displayed value before the binding runs.
            -- Keep the raw event argument to test its independent DB rounding.
            local pointerValue, step = value, w._msuf2Step
            if step and step >= 1 and value ~= math.floor(value) then
                local low, high = w:GetMinMaxValues()
                pointerValue = low + math.floor(((value - low) / step) + 0.5) * step
                pointerValue = math.max(low, math.min(high, pointerValue))
            end
            w:SetValue(pointerValue)
            World.FireScript(w, "OnValueChanged", value)
            World.FireScript(w, "OnMouseUp", "LeftButton")
        end
        mw:RunTimers()
    end
    local function Find(page, suffix)
        suffix = "." .. suffix:lower()
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if record.pageKey == page and record.controlId:sub(-#suffix) == suffix then
                return assert(M.RuntimeControlCatalog.Get(record.controlId).widget)
            end
        end
        error("GroupBars control missing: " .. page .. suffix)
    end
    local function Own(w, page)
        while w do
            for _, id in ipairs(SECTION_IDS[page]) do
                local section = M.cache[page].sections[id]
                if w == section or w == section._msuf2CollapsibleEntry.header then return id end
            end
            w = w.GetParent and w:GetParent()
        end
    end
    local function Controls(page)
        local out = {}
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local w = M.RuntimeControlCatalog.Get(record.controlId).widget
            if record.pageKey == page and w and Own(w, page) then
                local cmd = Command(w)
                if cmd and cmd.get and cmd.set then out[#out + 1] = w end
            end
        end
        table.sort(out, function(a, b) return a._msuf2RuntimeControlRecord.controlId < b._msuf2RuntimeControlRecord.controlId end)
        return out
    end
    local function NativeText(region)
        if type(region) == "string" or type(region) == "number" then return tostring(region) end
        if region and region.GetText then
            local value = region:GetText()
            if type(value) == "string" or type(value) == "number" then return tostring(value) end
        end
    end
    local function NativeDisplay(page, w)
        local command, record = Command(w), w._msuf2RuntimeControlRecord
        local kind = command and command.kind or record and record.kind
        local value
        if kind == "toggle" then
            for _, id in ipairs(SECTION_IDS[page]) do
                local section = M.cache[page].sections[id]
                if section._msuf2CollapsibleEntry.header == w then value = Pack(section:IsShown()) break end
            end
            value = value or Pack(w:GetChecked())
        elseif kind == "textinput" then value = Pack(w:GetText())
        else value = Pack(w:GetValue()) end
        local choices = {}
        for _, button in ipairs(w.buttons or {}) do
            choices[#choices + 1] = { button._msuf2Value, button._msuf2Active == true,
                NativeText(button._msuf2Label) or NativeText(button.text), button:IsShown(), button:IsEnabled() }
        end
        return { value = value, label = NativeText(w._msuf2Label), title = NativeText(w._msuf2Title),
            text = NativeText(w), edit = NativeText(w.editBox), choices = choices,
            switchPaint = w._msuf2SwitchPaintedChecked, shown = w:IsShown(), enabled = w:IsEnabled() }
    end
    local function AssertNativeValue(page, w, tag, model)
        local command = Command(w)
        model = model or Pack(command.get())
        local displayed = NativeDisplay(page, w)
        local actual, expected = displayed.value[1], model[1]
        local same = Encode(model, ids) == Encode(displayed.value, ids)
        if command and command.kind == "slider" and type(actual) == "number" and type(expected) == "number" then
            same = math.abs(actual - expected) < 0.0001
            local lo, hi = w:GetMinMaxValues()
            if not same and type(lo) == "number" and type(hi) == "number" and (expected < lo or expected > hi) then
                -- Native sliders may clamp imported out-of-range edge values.
                same = math.abs(actual - math.max(lo, math.min(hi, expected))) < 0.0001
            end
            if w.editBox and w._msuf2FormatValue then
                assert(displayed.edit == tostring(w._msuf2FormatValue(expected)),
                    "displayed slider text/model drift: " .. tag .. ":" .. w._msuf2RuntimeControlRecord.controlId)
            end
        end
        assert(same, "displayed value/model drift: " .. tag .. ":" .. w._msuf2RuntimeControlRecord.controlId)
        if #displayed.choices > 0 then
            local active = 0
            for _, choice in ipairs(displayed.choices) do
                if choice[2] then
                    active = active + 1
                    assert(choice[1] == expected, "displayed segment/model drift: " .. tag)
                end
            end
            assert(active == 1, "displayed segment has no unique active choice: " .. tag)
        end
        if displayed.switchPaint ~= nil then
            assert(displayed.switchPaint == expected, "displayed switch paint/model drift: " .. tag)
        end
        return model, displayed
    end
    local function CheckDisplays(page, tag, selected)
        local states = {}
        for _, w in ipairs(selected and { selected } or Controls(page)) do
            local model, displayed = AssertNativeValue(page, w, tag)
            states[#states + 1] = { w._msuf2RuntimeControlRecord.controlId, model, displayed }
        end
        Add(tag .. ":displayed", states)
    end
    local function ActionLabels(popup)
        local states = {}
        for _, w in ipairs(mw.world.widgets.frames) do
            if w:GetParent() == popup then
                states[#states + 1] = { NativeText(w._msuf2Label), NativeText(w._msuf2Title), NativeText(w),
                    w:GetValue(), w:GetChecked(), w:IsShown(), w:IsEnabled() }
            end
        end
        return NativeText(popup.title), states
    end
    local function Gates(page)
        local out = {}
        for _, w in ipairs(Controls(page)) do out[w._msuf2RuntimeControlRecord.controlId] = { w:IsShown(), w:IsEnabled() } end
        return out
    end
    local function Open(page, scope)
        assert(mw:Select(page))
        Input(Find(page, "scope.selector"), scope)
        assert(GP.CurrentScope() == scope, "real scope selection failed")
        for _, id in ipairs(SECTION_IDS[page]) do
            local section = M.cache[page].sections[id]
            local shell = section._msuf2CollapsibleEntry
            -- Package132f declares these lazy headers before this body's builder.
            local prepared
            if candidate and page == "gf_layout" then
                M.ControlSchema.Section(section, "group")
                prepared = shell.header._msuf2ControlSchema
            end
            shell.SetOpenImmediate(true)
            if prepared then assert(shell.header._msuf2ControlSchema == prepared, "lazy header declared twice: " .. id) end
        end
        mw:RunTimers()
        M.Refresh(M.cache[page].ctx)
        local scopeWidget = Find(page, "scope.selector")
        local _, displayed = AssertNativeValue(page, scopeWidget, "scope:" .. scope, Pack(GP.CurrentScope()))
        Add("scope-native-display", page, scope, displayed)
    end
    local serial = 0
    local function Index(w)
        if ids[w] then return end
        serial = serial + 1
        ids[w] = serial
        for _, region in ipairs(w.regions or {}) do Index(region) end
    end
    env.GameTooltip.SetOwner = function(_, ...) tips[#tips + 1] = { "owner", ... } end
    env.GameTooltip.SetText = function(_, ...) tips[#tips + 1] = { "title", ... } end
    env.GameTooltip.AddLine = function(_, ...) tips[#tips + 1] = { "line", ... } end
    env.GameTooltip.Show = function() tips[#tips + 1] = { "show" } end
    env.GameTooltip.Hide = function() tips[#tips + 1] = { "hide" } end
    local function Observe(page, tag)
        local declared, seen, declarationIds = { card = 0, text = 0, preview = 0 }, {}, {}
        local inherited, inheritedSeen, inheritedCounts = {}, {}, { summary = 0, actions = 0, previewLabel = 0 }
        local previewLabelOwners = {}
        local expectedPreviewParents = { nameContent = true, ["text.hp.content"] = true, ["text.power.content"] = true }
        if candidate then
            for _, id in ipairs(SECTION_IDS[page]) do
                local shell = assert(M.cache[page].sections[id]._msuf2CollapsibleEntry)
                local summary = assert(shell._msuf2UXSummary, "inherited section summary missing: " .. id)
                assert(not inherited[summary], "inherited section summary reused across owners")
                inherited[summary] = { shell.header, "section.summary", "font", "summary", id }
                if id ~= "text" then
                    local actions = assert(shell._msuf2SectionActions, "inherited section actions missing: " .. id)
                    assert(not inherited[actions], "inherited section actions reused across owners")
                    inherited[actions] = { shell.header, "section.actions", "button", "actions", id }
                else assert(shell._msuf2SectionActions == nil, "text section unexpectedly gained inherited actions") end
            end
            for _, native in ipairs(nativeTextPreviews) do
                if Own(native.parent, page) then
                    assert(page == "gf_layout", "Bars unexpectedly created a shared text preview")
                    local parentSpec = assert(native.parent._msuf2ControlSchema, "native preview card has no declaration")
                    local parentId = parentSpec.id
                    assert(expectedPreviewParents[parentId] and parentSpec.kind == "card" and parentSpec.scope == "group"
                        and parentSpec.applyDomain == "presentation" and parentSpec.owner == native.parent,
                        "unexpected shared preview card owner: " .. tostring(parentId))
                    assert(previewLabelOwners[parentId] == nil, "shared preview card reused: " .. parentId)
                    local label, value = assert(native.label), assert(native.value)
                    local valueSpec = assert(value._msuf2ControlSchema, "native preview value declaration missing")
                    assert(valueSpec.id == parentId .. ".preview" and valueSpec.kind == "preview" and valueSpec.scope == "group"
                        and valueSpec.applyDomain == "preview" and valueSpec.owner == value and valueSpec.label == label
                        and value:GetParent() == native.parent and label:GetParent() == native.parent,
                        "shared preview label/value/card identity drift: " .. parentId)
                    assert(label:GetObjectType() == "FontString" and not inherited[label], "shared preview label instance reused")
                    inherited[label] = { native.parent, "shared.preview.label", "text", "previewLabel", parentId }
                    previewLabelOwners[parentId] = 0
                end
            end
        end
        local function CheckDeclaration(widget)
            if not candidate or seen[widget] then return end
            seen[widget] = true
            local spec = widget._msuf2ControlSchema
            local shared = inherited[widget]
            if shared then
                assert(spec and spec.id == shared[2] and spec.kind == shared[3] and spec.scope == "shared"
                    and spec.applyDomain == "presentation" and spec.owner == widget and widget:GetParent() == shared[1],
                    "inherited section owner/declaration drift: " .. shared[5] .. ":" .. shared[2])
                inheritedSeen[widget] = true
                inheritedCounts[shared[4]] = inheritedCounts[shared[4]] + 1
                if shared[4] == "previewLabel" then
                    assert(spec.labelKey == "Preview", "shared preview label key drift")
                    previewLabelOwners[shared[5]] = previewLabelOwners[shared[5]] + 1
                end
                return
            end
            if spec then
                local wanted = DECLARATIONS[page][spec.id]
                assert(wanted and wanted[1] == spec.kind and wanted[2] == spec.scope and wanted[3] == spec.applyDomain,
                    "declaration id/kind/scope/applyDomain drift: " .. tostring(spec.id) .. "/" .. tostring(spec.applyDomain))
                assert(not declarationIds[spec.id], "duplicate declaration: " .. spec.id)
                declarationIds[spec.id] = true
            end
            if widget._msuf2ControlCard then assert(spec and spec.kind == "card", "undeclared native card") end
            if spec and declared[spec.kind] then
                assert(spec.owner == widget and spec.scope == "group", "presentation owner drift")
                declared[spec.kind] = declared[spec.kind] + 1
            end
        end
        for _, w in ipairs(mw.world.widgets.frames) do Index(w) end
        for _, w in ipairs(mw.world.widgets.frames) do
            if Own(w, page) then
                CheckDeclaration(w)
                local points = {}
                for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
                Add(tag .. ":layout", w, w:GetParent(), w.width, w.height, w.text, points, w:IsShown(), w:IsEnabled(), w._msuf2CursorY)
                for _, region in ipairs(w.regions or {}) do
                    CheckDeclaration(region)
                    local rp = {}
                    for i = 1, region:GetNumPoints() do rp[i] = Pack(region:GetPoint(i)) end
                    Add(tag .. ":region", region, region.text, region.width, region.height, rp, region:IsShown())
                end
            end
        end
        if candidate then
            for id in pairs(DECLARATIONS[page]) do assert(declarationIds[id], "missing declaration: " .. id) end
            local bars = page == "gf_bars"
            for widget, shared in pairs(inherited) do
                assert(inheritedSeen[widget], "inherited section row was not inventoried: " .. shared[5] .. ":" .. shared[2])
            end
            assert(inheritedCounts.summary == 3 and inheritedCounts.actions == (bars and 3 or 2),
                "inherited section summary/actions census drift")
            assert(inheritedCounts.previewLabel == (bars and 0 or 3), "inherited preview label census drift")
            if bars then assert(next(previewLabelOwners) == nil, "Bars inherited a foreign text preview owner")
            else
                for parentId in pairs(expectedPreviewParents) do
                    assert(previewLabelOwners[parentId] == 1, "shared preview label not observed exactly once: " .. parentId)
                end
            end
            assert(declared.card == (bars and 3 or 14), "native card declaration coverage drift")
            assert(declared.text == (bars and 1 or 4), "static text declaration coverage drift")
            assert(declared.preview == (bars and 0 or 3), "retained preview declaration coverage drift")
        end
        for _, w in ipairs(Controls(page)) do
            tips = {}
            World.FireScript(w, "OnEnter")
            World.FireScript(w, "OnLeave")
            local lo, hi = w:GetMinMaxValues()
            Add(tag .. ":control", w._msuf2RuntimeControlRecord, w._msuf2SearchMeta, w._msuf2SearchText,
                lo, hi, w.valueStep, w.GetValues and w:GetValues() or w.values, Pack(Command(w).get()), NativeDisplay(page, w), tips)
        end
    end
    local refresh = M.Refresh
    M.Refresh = function(...) refreshes = refreshes + 1 return refresh(...) end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...) calls[#calls + 1] = { name, ... } return fn(...) end end
    end
    local function Setup(page, scope, edge, w, missing)
        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
            local conf, defaults = GP.Conf(kind), F.CopySnapshot(factory["gf_" .. kind])
            for key in pairs(conf) do conf[key] = nil end
            for key, value in pairs(defaults) do conf[key] = value end
            conf.enabled = true
        end
        local conf = GP.Conf(scope)
        if edge then
            conf.dispelOverlayTrigger, conf.dispelSymbolTrigger = "GROUP", "ANY"
            conf.dispelOverlayAlpha, conf.dispelOverlayLayer, conf.dispelSymbolSpacing = 0, 0, 0
            conf.nameFontSize, conf.hpFontSize, conf.powerFontSize = 0, 0, 0
            conf.hpTextRightFontSize, conf.powerTextRightFontSize = nil, 0
            conf.detachedPowerBarWidth, conf.rangeFadeAlpha, conf.offlineAlpha = nil, 0, 0
            conf.textDelimiter, conf.hpTextRightHidePercentSymbol, conf.hpAbsorbIcon = "", false, true
        end
        for _, key in ipairs({ "dispelOverlayEnabled", "dispelSymbolEnabled", "debuffStripeEnabled", "powerBarEnabled",
            "powerBarBorderEnabled", "rangeFadeEnabled", "offlineFadeEnabled", "showName", "showHPText", "showPowerText", "showPower" }) do
            conf[key] = true
        end
        conf.powerHeight, conf.dispelSymbolMode, conf.hideOfflineEnabled = 6, "ALL", false
        conf.textLeft, conf.textCenter, conf.textRight = "CURRENT", "CURMAXPERCENTABSORB", "CURMAXPERCENTABSORB"
        conf.powerTextLeft, conf.powerTextCenter, conf.powerTextRight = "CURRENT", "PERCENT", "PERCENT"
        local id = w and w._msuf2RuntimeControlRecord.controlId or ""
        conf.powerBarDetached = id:find("detachedpowerbar", 1, true) ~= nil
        if page == "gf_layout" then
            local tab = "name"
            if id:find("text.hp.", 1, true) or id:find("showhptext", 1, true) or id:find("textdelimiter", 1, true)
                or id:find("hptextreverse", 1, true) or id:find("healthtextdecimals", 1, true) or id:find("hpfullvalueshort", 1, true) then tab = "hp" end
            if id:find("text.power.", 1, true) or id:find("powertextdelimiter", 1, true) then tab = "power" end
            if id:find("textlayer", 1, true) then tab = "advanced" end
            for _, kind in ipairs({ "hp", "power" }) do
                Input(Find(page, "text.workspace_tab"), kind)
                Input(Find(page, "text." .. kind .. ".slot_selector"), edge and "right" or "center")
                Input(Find(page, "text." .. kind .. ".move_together"), false)
            end
            Input(Find(page, "text.workspace_tab"), tab)
        end
        -- Clear only this control's stored key after all setup writes, then use
        -- the real refresh/input owners with that absence still in place.
        for _, key in ipairs(missing or {}) do conf[key] = nil end
        local beforeRefresh = missing and F.CopySnapshot(env.MSUF_DB)
        if missing then calls, refreshes, previews = {}, 0, {} end
        M.Refresh(M.cache[page].ctx)
        mw:RunTimers()
        for _, key in ipairs(missing or {}) do assert(conf[key] == nil, "refresh materialized missing key: " .. key) end
        CheckDisplays(page, "setup:" .. scope .. ":" .. tostring(edge) .. ":" .. id, w)
        M.ClearHistory()
        return beforeRefresh
    end
    local function Value(w, edge)
        local cmd, old = Command(w), Command(w).get()
        local raw = edge and RAW_NUMBER_CASES[w._msuf2RuntimeControlRecord.controlId:match("[^.]+$")]
        if raw then return raw.value end
        if cmd.kind == "toggle" then return not old end
        if cmd.kind == "slider" then
            local lo, hi = w:GetMinMaxValues()
            if w.valueStep and w.valueStep < 1 then return old == 0.35 and 0.65 or 0.35 end
            return old == hi and lo or hi
        end
        local values = w.GetValues and w:GetValues() or w.values
        if type(values) == "function" then values = values() end
        for i = #values, 1, -1 do
            local value = values[i].value or values[i][1]
            if value ~= old then return value end
        end
        error("no alternate real input")
    end
    local count, missingCount = 0, 0
    for _, scope in ipairs((mode == "push" or narrow or mode == "contracts") and { "party" } or { "party", "raid", "mythicraid" }) do
        if core.Client.SupportsGroupKind(scope) then
            for _, page in ipairs({ "gf_bars", "gf_layout" }) do
                Open(page, scope)
                Add("preview-hook-order", scope, page, previewHooks)
                local controls = Controls(page)
                count = count + #controls
                if candidate then
                    for _, w in ipairs(controls) do assert(w._msuf2ControlSchema, "missing replacing row: " .. w._msuf2RuntimeControlRecord.controlId) end
                end
                for _, edge in ipairs((mode == "push" or narrow or mode == "contracts") and { false } or { false, true }) do
                    Setup(page, scope, edge)
                    local prefix = scope .. ":" .. page .. ":" .. tostring(edge)
                    Observe(page, prefix)
                    for _, w in ipairs((narrow or mode == "contracts") and {} or controls) do
                        for _, missing in ipairs(edge and { false } or { false, MissingKeys(w) }) do
                            local beforeRefresh = Setup(page, scope, edge, w, missing)
                            assert(w:IsEnabled(), "input is gated: " .. w._msuf2RuntimeControlRecord.controlId)
                            local tag = prefix .. ":" .. w._msuf2RuntimeControlRecord.controlId
                            if missing then
                                missingCount = missingCount + 1
                                tag = tag .. ":missing:" .. table.concat(missing, ",")
                                Add(tag .. ":refresh", Diff(beforeRefresh, env.MSUF_DB), Pack(Command(w).get()), NativeDisplay(page, w),
                                    calls, refreshes, previews, Gates(page))
                            end
                            local before, value = F.CopySnapshot(env.MSUF_DB), Value(w, edge)
                            calls, refreshes, previews = {}, 0, {}
                            Input(w, value)
                            local raw = edge and RAW_NUMBER_CASES[w._msuf2RuntimeControlRecord.controlId:match("[^.]+$")]
                            -- Native BindSlider rounds integer-step pointer input before the page setter.
                            if raw then
                                assert(GP.Conf(scope)[raw.key] == math.floor(raw.value + 0.5),
                                    "native integer-step input drift: " .. raw.key)
                            end
                            local after = F.CopySnapshot(env.MSUF_DB)
                            CheckDisplays(page, tag .. ":input", w)
                            Add(tag .. ":input", value, Diff(before, after), Pack(Command(w).get()), NativeDisplay(page, w),
                                calls, refreshes, previews, Gates(page))
                            local beforeExplicit = F.CopySnapshot(env.MSUF_DB)
                            M.Refresh(M.cache[page].ctx) mw:RunTimers()
                            CheckDisplays(page, tag .. ":explicit-refresh", w)
                            Add(tag .. ":explicit-refresh", Diff(beforeExplicit, env.MSUF_DB), NativeDisplay(page, w))
                            local undo = M.Undo()
                            mw:RunTimers()
                            CheckDisplays(page, tag .. ":automatic-undo", w)
                            Add(tag .. ":undo", undo, Diff(before, env.MSUF_DB), Pack(Command(w).get()), NativeDisplay(page, w))
                            local redo = M.Redo()
                            mw:RunTimers()
                            CheckDisplays(page, tag .. ":automatic-redo", w)
                            Add(tag .. ":redo", redo, Diff(after, env.MSUF_DB), Pack(Command(w).get()), NativeDisplay(page, w))
                            Setup(page, scope, edge, w, missing)
                            before = F.CopySnapshot(env.MSUF_DB)
                            core.Util.InCombat("PLAYER_REGEN_DISABLED")
                            env.InCombatLockdown = function() return true end
                            calls, refreshes = {}, 0
                            Input(w, value)
                            CheckDisplays(page, tag .. ":combat-refusal", w)
                            Add(tag .. ":combat", Diff(before, env.MSUF_DB), Pack(Command(w).get()), NativeDisplay(page, w), calls, refreshes, M.Undo())
                            core.Util.InCombat("PLAYER_REGEN_ENABLED")
                            env.InCombatLockdown = function() return false end
                            mw:Fire("PLAYER_REGEN_ENABLED")
                            mw:RunTimers()
                            CheckDisplays(page, tag .. ":combat-resume", w)
                        end
                    end
                end
                if narrow or mode == "contracts" then
                elseif page == "gf_layout" then
                    local toggle = Find(page, "field.powerBarEnabled")
                    for _, height in ipairs({ "missing", 0 }) do
                        Setup(page, scope, true, toggle)
                        local conf = GP.Conf(scope)
                        conf.powerBarEnabled, conf.powerHeight = false, height == "missing" and nil or height
                        if height == "missing" then conf.powerHeight = nil end
                        M.Refresh(M.cache[page].ctx)
                        M.ClearHistory()
                        Input(toggle, true)
                        assert(conf.powerHeight == (scope == "party" and 6 or 4), "companion height was not restored")
                        local undo = M.Undo()
                        assert((height == "missing" and conf.powerHeight == nil) or conf.powerHeight == height, "Undo lost missing/zero companion")
                        mw:RunTimers() CheckDisplays(page, "power-companion:automatic-undo:" .. scope .. ":" .. tostring(height))
                        local undoHeight, redo = conf.powerHeight, M.Redo()
                        mw:RunTimers() CheckDisplays(page, "power-companion:automatic-redo:" .. scope .. ":" .. tostring(height))
                        Add("power-companion", scope, height, undo, undoHeight, redo, conf.powerHeight)
                    end
                else
                    local preview = Find(page, "field.dispelOverlayPreview")
                    Setup(page, scope, false, preview)
                    Input(preview, true)
                    World.FireScript(preview, "OnHide")
                    CheckDisplays(page, "preview-hide:" .. scope, preview)
                    Add("preview-hide", scope, env.MSUF_DispelOverlayPreviewMode, preview:GetChecked(), NativeDisplay(page, preview), previews)
                end
                if mode == "push" then Setup(page, scope, true) Observe(page, scope .. ":" .. page .. ":edge") end
                for _, id in ipairs((narrow or mode == "contracts") and {} or SECTION_IDS[page]) do
                    local actions = M.cache[page].sections[id]._msuf2CollapsibleEntry._msuf2SectionActions
                    if actions then
                        actions:Click()
                        local popup = assert(actions._msuf2GetSectionPopup())
                        local reset
                        for _, w in ipairs(mw.world.widgets.frames) do
                            if w:GetParent() == popup and w._msuf2Label and w._msuf2Label:GetText() == "Reset section" then reset = w end
                        end
                        assert(reset, "native section Reset missing")
                        Add("section-action-native-labels", scope, page, id, NativeText(actions._msuf2Label), ActionLabels(popup))
                        local before = F.CopySnapshot(env.MSUF_DB)
                        reset:Click()
                        mw:RunTimers()
                        Add("reset", scope, page, id, Diff(before, env.MSUF_DB))
                        CheckDisplays(page, "reset:" .. scope .. ":" .. id)
                        local resetUndo = M.Undo() mw:RunTimers()
                        CheckDisplays(page, "reset:automatic-undo:" .. scope .. ":" .. id)
                        local resetRedo = M.Redo() mw:RunTimers()
                        CheckDisplays(page, "reset:automatic-redo:" .. scope .. ":" .. id)
                        Add("reset-history", scope, page, id, resetUndo, resetRedo)
                        before = F.CopySnapshot(env.MSUF_DB)
                        Add("copy", scope, page, id, popup._msuf2CopySection(scope == "party" and "raid" or "party"))
                        mw:RunTimers()
                        Add("copy-diff", Diff(before, env.MSUF_DB))
                        CheckDisplays(page, "copy-helper:" .. scope .. ":" .. id)
                        local copyUndo = M.Undo() mw:RunTimers()
                        CheckDisplays(page, "copy-helper:automatic-undo:" .. scope .. ":" .. id)
                        local copyRedo = M.Redo() mw:RunTimers()
                        CheckDisplays(page, "copy-helper:automatic-redo:" .. scope .. ":" .. id)
                        Add("copy-helper-history", scope, page, id, copyUndo, copyRedo, ActionLabels(popup))
                        if not popup:IsShown() then actions:Click() end
                        local copy, destination
                        for _, widget in ipairs(mw.world.widgets.frames) do
                            if widget:GetParent() == popup then
                                if NativeText(widget._msuf2Label) == "Copy section" then copy = widget end
                                if widget._msuf2OnValueChanged then destination = widget end
                            end
                        end
                        assert(copy and destination, "native section Copy controls missing")
                        if copy:IsShown() and copy:IsEnabled() then
                            local targetScope = scope == "party" and "raid" or "party"
                            destination:SetValue(targetScope)
                            destination._msuf2OnValueChanged(targetScope)
                            before = F.CopySnapshot(env.MSUF_DB)
                            local history, historyCalls = M.RunWithHistory, 0
                            M.RunWithHistory = function(...)
                                historyCalls = historyCalls + 1
                                return history(...)
                            end
                            copy:Click("LeftButton")
                            M.RunWithHistory = history
                            assert(historyCalls == 1, "native Copy did not reach history owner")
                            mw:RunTimers()
                            Add("copy-native", scope, page, id, destination:GetValue(), Diff(before, env.MSUF_DB), historyCalls)
                            CheckDisplays(page, "copy-native:" .. scope .. ":" .. id)
                            local undo = M.Undo() mw:RunTimers()
                            CheckDisplays(page, "copy-native:automatic-undo:" .. scope .. ":" .. id)
                            local redo = M.Redo() mw:RunTimers()
                            CheckDisplays(page, "copy-native:automatic-redo:" .. scope .. ":" .. id)
                            Add("copy-native-history", scope, page, id, undo, redo, ActionLabels(popup))
                        else Add("copy-native-gated", scope, page, id, copy:IsShown(), copy:IsEnabled()) end
                        popup:Hide()
                    end
                end
                mw:Select("home")
                mw:Select(page)
                CheckDisplays(page, "reopen:" .. scope .. ":" .. page)
                Add("reopen", scope, page, Gates(page))
            end
        end
    end
    return rows, count, missingCount
end
local started = os.clock()
local baseline, count, missingCount = Replay(scratch, false)
local actual, _, actualMissingCount = Replay(sourceOverride, true)
assert(missingCount == actualMissingCount, "missing-key case count drift")
assert(#baseline == #actual, "observation count drift: " .. #baseline .. " / " .. #actual)
for i = 1, #baseline do
    if baseline[i] ~= actual[i] then
        error("GroupBars parity drift at " .. i .. "\nparent: " .. baseline[i] .. "\ncandidate: " .. actual[i])
    end
end
if mode == "push" or mode == "full" then
    narrow = true
    local before, after = Replay(scratch, false), Replay(sourceOverride, true)
    assert(#before == #after, "narrow observation count drift")
    for i = 1, #before do assert(before[i] == after[i], "400px GroupBars parity drift at " .. i .. "\nparent: " .. before[i] .. "\ncandidate: " .. after[i]) end
end
os.remove(scratch)
print("menu_group_bars_schema_parity_smoke " .. mode .. " " .. flavor .. ": " .. count .. " scoped controls; " .. #baseline
    .. " observations; " .. missingCount .. " missing-key cases; "
    .. (mode == "push" and "party default inputs plus edge snapshots" or mode == "full"
        and "all scopes/default/edge/raw-fraction inputs" or "observation-only")
    .. "; DB, native display/text/labels, apply, history, combat, scope, tabs, reset/copy, tooltip hooks"
    .. " and 17 cards/5 texts/3 previews per scope OK ("
    .. string.format("%.2fs", os.clock() - started) .. ")")
