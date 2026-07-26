local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function Has(source, needle, message)
    assert(source:find(needle, 1, true), message)
end

local function Count(source, needle)
    local count, from = 0, 1
    while true do
        local at = source:find(needle, from, true)
        if not at then return count end
        count, from = count + 1, at + #needle
    end
end

local function Slice(source, first, last, label)
    local startAt = assert(source:find(first, 1, true), label .. " start marker is missing")
    local endAt = assert(source:find(last, startAt + #first, true), label .. " end marker is missing")
    return source:sub(startAt, endAt - 1)
end

local pagesRoot = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local colors = Read(pagesRoot .. "MSUF_Menu2_AdvancedColors.lua")

-- The semantic resolver must remain behind the RGB button click. Constructing
-- or idling Menu2 may not resolve colors or install recurring work.
local referenceHelper = Slice(widgets,
    "function W.AttachContextColorReferences",
    "local function PositionedContextColorCard",
    "context-color reference helper")
Has(referenceHelper, "options.getTargets = function()", "semantic references are not deferred behind getTargets")
Has(referenceHelper, "local resolver = M.ResolveContextColorReferences", "semantic resolver is not looked up lazily")
Has(referenceHelper, "W.AttachContextColorShortcut(card, options)", "semantic references bypass the shared RGB shortcut")
Has(referenceHelper, "options.isRelevant = function()", "semantic references do not hide irrelevant empty mappings")
Has(referenceHelper, "local count = type(resolvedReferences) == \"table\" and #resolvedReferences or 0",
    "semantic relevance does not inspect only the cheap raw reference list")
local deferredAt = assert(referenceHelper:find("options.getTargets = function()", 1, true))
local resolverAt = assert(referenceHelper:find("local resolver = M.ResolveContextColorReferences", 1, true))
assert(resolverAt > deferredAt, "semantic targets are resolved before the deferred click provider")
for _, forbidden in ipairs({ 'SetScript("OnUpdate"', "RegisterEvent", "RegisterUnitEvent", "C_Timer" }) do
    assert(not referenceHelper:find(forbidden, 1, true), "semantic reference helper adds recurring work: " .. forbidden)
end

local openHelper = Slice(widgets,
    "function W.OpenContextColors",
    "function W.AttachContextColorShortcut",
    "context-color open helper")
Has(openHelper, "ResolveContextColorOption(opts.getTargets or opts.targets, {})",
    "the deferred target provider is not resolved by the open path")
Has(openHelper, "math.max(1, math.min(4, tonumber(opts.maxTargets) or 4))",
    "the context-color popup no longer enforces its four-target maximum")
Has(openHelper, "owner._msuf2ContextColorAllowDisabled == true",
    "opt-in colors can no longer be preconfigured while their feature is disabled")

local shortcutHelper = Slice(widgets,
    "function W.AttachContextColorShortcut",
    "function W.AttachContextColorReferences",
    "context-color shortcut")
Has(widgets, "local function ContextColorShortcutsSuppressed(card)",
    "context-color shortcuts have no page-scoped suppression helper")
Has(shortcutHelper, "if ContextColorShortcutsSuppressed(card) then return nil end",
    "context-color shortcuts ignore page-scoped suppression")
Has(shortcutHelper, 'shortcut:SetScript("OnClick", function(self)', "RGB shortcut has no click handler")
Has(shortcutHelper, "W.OpenContextColors(card, options)", "RGB shortcut click does not open the deferred color context")
for _, forbidden in ipairs({ 'SetScript("OnUpdate"', "RegisterEvent", "RegisterUnitEvent", "C_Timer" }) do
    assert(not shortcutHelper:find(forbidden, 1, true), "RGB shortcut adds recurring work: " .. forbidden)
end

local boundColorHelper = Slice(widgets,
    "local function AttachBoundColorToContextCard",
    "function W.SetCollapsibleColorSwatches",
    "bound context-color helper")
Has(boundColorHelper, "owner._msuf2ContextColorAllowDisabled == true",
    "bound RGB shortcuts ignore the opt-in for disabled-state preconfiguration")

local colorsBuild = Slice(colors,
    "local function BuildColors(ctx)",
    'M.RegisterPage("opt_colors"',
    "native colors page")
Has(colorsBuild, "ctx.wrapper._msuf2SuppressContextColorShortcuts = true",
    "the native Colors page does not suppress redundant RGB shortcuts")

local registry = Slice(colors,
    "-- Feature pages reference these semantic ids",
    "local function BuildBarGradientColors",
    "semantic color registry")
Has(registry, "function M.ResolveContextColorReferences", "semantic color resolver is not exported")
Has(registry, "M.ContextColorReferenceFactories = CONTEXT_COLOR_FACTORIES", "semantic color registry is not exported")
for _, forbidden in ipairs({ 'SetScript("OnUpdate"', "RegisterEvent", "RegisterUnitEvent", "C_Timer", "M.TrackRefresh" }) do
    assert(not registry:find(forbidden, 1, true), "semantic registry adds recurring work: " .. forbidden)
end

local requiredRegistryIds = {
    "bar.absorb", "bar.heal_absorb", "bar.power_background", "bar.aggro_border",
    "bar.heal_prediction", "bar.purge_border", "bar.background_tint",
    "health.unified", "health.gradient.low", "health.gradient.mid", "health.gradient.high", "health.current",
    "unit.class.current", "unit.npc.current", "unit.pet",
    "highlight.mouseover", "highlight.boss_target", "portrait.border", "portrait.background", "font.global",
    "font.default.current",
    "text.inline_tot.current",
    "cast.interruptible", "cast.non_interruptible", "cast.interrupt_feedback", "cast.interrupt_unavailable",
    "cast.text", "cast.target_text", "cast.player_override", "cast.border", "cast.background",
    "cast.kick_ready", "cast.kick_not_ready",
    "aura.cooldown.safe", "aura.cooldown.warning", "aura.cooldown.urgent",
    "group.health", "group.background", "group.dead", "group.debuff_stripe",
    "group.target", "group.focus", "group.border", "group.aggro",
    "gameplay.timer", "gameplay.enter", "gameplay.leave", "gameplay.crosshair_in", "gameplay.crosshair_out",
    "power.current", "class_power.current", "class_power.text", "class_power.alt_mana", "gradient.health", "gradient.power",
}
for _, id in ipairs(requiredRegistryIds) do
    Has(registry, '"' .. id .. '"', "semantic color registry is missing " .. id)
end

-- Effective Health is dynamic: the popup must follow gradient, unified,
-- player/class, pet, and NPC resolution instead of inventing one static color.
local healthFactory = Slice(registry,
    'ContextFactory("health.current"',
    'ContextFactory("unit.class.current"',
    "dynamic health color factory")
for _, marker in ipairs({
    '"health.gradient.low"', '"health.gradient.mid"', '"health.gradient.high"',
    '"health.unified"', '"unit.pet"', "ContextNPCHealthTarget(context)", "ContextClassColor(context)",
}) do
    Has(healthFactory, marker, "dynamic health factory is missing " .. marker)
end

-- Castbar surface colors are RGBA, while inherited text/override values need
-- structural state restoration so Cancel does not turn inheritance into an
-- explicit override.
local castFactory = Slice(registry,
    "local function CastApiFactory",
    "local function AuraTableFactory",
    "castbar color factories")
Has(castFactory, "local state = ContextStoredState(G, keys, ApplyCastbarColors)",
    "castbar inherited colors do not capture their stored state")
Has(castFactory, "target.captureState, target.restoreState = state.captureState, state.restoreState",
    "castbar colors do not expose structural Cancel restoration")
Has(castFactory, 'ContextApiOrGeneral("cast.border"', "castbar border has no RGBA adapter")
Has(castFactory, 'ContextApiOrGeneral("cast.background"', "castbar background has no RGBA adapter")
Has(castFactory, '"castbarBorderA"', "castbar border alpha is not part of captured state")
Has(castFactory, '"castbarBgA"', "castbar background alpha is not part of captured state")
assert(Count(castFactory, "target.hasOpacity, target.getOpacity = true") >= 2,
    "castbar border/background do not both expose opacity")
assert(Count(castFactory, "target.captureState, target.restoreState") >= 3,
    "castbar text/override and RGBA factories lost structural state restoration")

-- Absorb RGB is global, but its opacity follows the selected Bars scope. The
-- contextual picker must preserve that split and restore newly-created scope
-- overrides structurally on Cancel.
local absorbFactory = Slice(registry,
    "local function ContextStoredApiScopedOpacity",
    "local function ContextApi",
    "scoped absorb color factory")
for _, marker in ipairs({
    "CurrentBarsScope()", "globalPage.BarScopeGet(opacityKey, fallback)",
    "globalPage.BarScopeSet(opacityKey, a, opacityReason)",
    'ContextDBRowsState(globalPage.ScopeDBKeys(scope) or {}, { opacityKey, "hlOverride" }, false)',
    "local _, _, _, legacyAlpha = ApiRGB", "generalState.restoreState(state.general)",
    "scopedState.restoreState(state.scoped)", "ApplyColors()",
}) do
    Has(absorbFactory, marker, "scoped absorb adapter is missing " .. marker)
end

-- Preview-only pages still need a deterministic NPC/ToT swatch without
-- consulting a nonexistent live unit through the runtime classifier.
local npcTextFactory = Slice(registry,
    "local function ContextTextNPCKind",
    "local function ContextNameEntityTarget",
    "preview NPC text factory")
Has(npcTextFactory, "if exists and common and type(common.UnitNPCKind) == \"function\" then",
    "preview NPC text still calls the live-unit classifier without a unit")
Has(npcTextFactory, "local preview = ContextPreviewUnitData(unit)",
    "preview NPC text has no deterministic menu fallback")

local pageSpecs = {
    {
        name = "Global Bars", file = "MSUF_Menu2_GlobalBars.lua",
        ids = { "gradient.health", "gradient.power", "bar.absorb", "bar.heal_absorb", "bar.heal_prediction",
            "bar.aggro_border", "bar.purge_border", "highlight.boss_target" },
    },
    {
        name = "Auras", file = "MSUF_Menu2_Auras.lua",
        ids = { "aura.cooldown.safe", "aura.cooldown.warning", "aura.cooldown.urgent" },
    },
    {
        name = "Global Castbars", file = "MSUF_Menu2_GlobalCastbars.lua",
        ids = { "cast.interruptible", "cast.non_interruptible", "cast.interrupt_feedback", "cast.interrupt_unavailable",
            "cast.background", "cast.border", "cast.text", "font.global", "cast.kick_ready", "cast.kick_not_ready" },
    },
    {
        name = "Unit Visuals", file = "MSUF_Menu2_UnitFrameVisuals.lua",
        ids = { "portrait.border", "portrait.background", "power.current", "bar.power_background",
            "cast.player_override", "unit.class.current", "cast.interruptible", "cast.non_interruptible",
            "cast.interrupt_feedback", "cast.background", "cast.border", "cast.text", "cast.target_text" },
    },
    {
        name = "Unit Sections", file = "MSUF_Menu2_UnitSections.lua",
        ids = { "health.gradient.low", "health.gradient.mid", "health.gradient.high", "health.unified",
            "health.current", "unit.pet", "bar.background_tint", "highlight.boss_target", "text.inline_tot.current" },
    },
    {
        name = "Unit Alpha", file = "MSUF_Menu2_UnitAlpha.lua",
        ids = { "health.gradient.low", "health.gradient.mid", "health.gradient.high", "health.unified",
            "health.current", "unit.pet", "bar.background_tint", "power.current", "bar.power_background" },
    },
    {
        name = "Group Layout", file = "MSUF_Menu2_GroupLayout.lua",
        ids = { "health.current", "group.health", "group.background", "group.dead" },
    },
    {
        name = "Group Bars", file = "MSUF_Menu2_GroupBars.lua",
        ids = { "group.debuff_stripe", "power.current", "group.background" },
    },
    {
        name = "Group Indicators", file = "MSUF_Menu2_GroupIndicators.lua",
        ids = { "group.target", "group.focus", "group.border", "group.aggro" },
    },
    {
        name = "Advanced Gameplay", file = "MSUF_Menu2_AdvancedGameplay.lua",
        ids = { "gameplay.timer", "gameplay.enter", "gameplay.leave", "gameplay.crosshair_in", "gameplay.crosshair_out" },
    },
    {
        name = "Global Misc", file = "MSUF_Menu2_GlobalMisc.lua",
        ids = { "highlight.mouseover" },
    },
    {
        name = "Global Fonts", file = "MSUF_Menu2_GlobalFonts.lua",
        ids = { "font.default.current" },
    },
    {
        name = "Advanced Class Power", file = "MSUF_Menu2_AdvancedClassPower.lua",
        ids = { "class_power.current", "class_power.text", "class_power.alt_mana" },
    },
}

local contextPrefixes = {
    bar = true, health = true, unit = true, highlight = true, portrait = true, font = true,
    cast = true, aura = true, group = true, gameplay = true, power = true, class_power = true, gradient = true,
    text = true,
}

local function IsContextId(value)
    local prefix = value:match("^([a-z_]+)%.")
    return prefix ~= nil and contextPrefixes[prefix] == true and value:match("^[a-z_]+%.[a-z0-9_.]+$") ~= nil
end

local function FindBalanced(source, openAt, openChar, closeChar)
    local depth, quote, i = 0, nil, openAt
    while i <= #source do
        local ch, nextCh = source:sub(i, i), source:sub(i + 1, i + 1)
        if quote then
            if ch == "\\" then i = i + 2
            elseif ch == quote then quote, i = nil, i + 1
            else i = i + 1 end
        elseif ch == '"' or ch == "'" then
            quote, i = ch, i + 1
        elseif ch == "-" and nextCh == "-" then
            local newline = source:find("\n", i + 2, true)
            i = newline and (newline + 1) or (#source + 1)
        else
            if ch == openChar then depth = depth + 1 end
            if ch == closeChar then
                depth = depth - 1
                if depth == 0 then return i end
            end
            i = i + 1
        end
    end
    return nil
end

local function ExtractReferenceCalls(source, pageName)
    local calls, from = {}, 1
    while true do
        local startAt, markerEnd = source:find("W%.AttachContextColorReferences%s*%(", from)
        if not startAt then return calls end
        local openAt = assert(source:find("(", startAt, true))
        local closeAt = assert(FindBalanced(source, openAt, "(", ")"), pageName .. " has an unbalanced context-color call")
        calls[#calls + 1] = source:sub(startAt, closeAt)
        from = math.max(closeAt + 1, markerEnd + 1)
    end
end

local function AssertTableMappingsAtMostFour(call, pageName)
    local stack, quote, value, i = {}, nil, nil, 1
    while i <= #call do
        local ch, nextCh = call:sub(i, i), call:sub(i + 1, i + 1)
        if quote then
            if ch == "\\" then
                value, i = value .. ch .. nextCh, i + 2
            elseif ch == quote then
                for level = 1, #stack do
                    if IsContextId(value) then stack[level][value] = true end
                end
                quote, value, i = nil, nil, i + 1
            else
                value, i = value .. ch, i + 1
            end
        elseif ch == '"' or ch == "'" then
            quote, value, i = ch, "", i + 1
        elseif ch == "-" and nextCh == "-" then
            local newline = call:find("\n", i + 2, true)
            i = newline and (newline + 1) or (#call + 1)
        elseif ch == "{" then
            stack[#stack + 1] = {}
            i = i + 1
        elseif ch == "}" then
            local ids = assert(stack[#stack], pageName .. " has an unmatched table close")
            local count, names = 0, {}
            for id in pairs(ids) do count, names[#names + 1] = count + 1, id end
            table.sort(names)
            assert(count <= 4, pageName .. " maps more than four colors in one table: " .. table.concat(names, ", "))
            stack[#stack] = nil
            i = i + 1
        else
            i = i + 1
        end
    end
    assert(#stack == 0, pageName .. " has an unbalanced context-color table")
    local explicitMax = call:match("maxTargets%s*=%s*(%d+)")
    assert(not explicitMax or tonumber(explicitMax) <= 4, pageName .. " requests more than four context colors")
end

local referencedIds = {}
for _, spec in ipairs(pageSpecs) do
    local source = Read(pagesRoot .. spec.file)
    local calls = ExtractReferenceCalls(source, spec.name)
    assert(#calls > 0, spec.name .. " has no context-color attachment")
    for _, id in ipairs(spec.ids) do
        Has(source, '"' .. id .. '"', spec.name .. " is missing color cross-reference " .. id)
        referencedIds[id] = true
    end
    for _, call in ipairs(calls) do
        AssertTableMappingsAtMostFour(call, spec.name)
        for id in call:gmatch('"([a-z_]+%.[a-z0-9_.]+)"') do
            if IsContextId(id) then referencedIds[id] = true end
        end
    end
end

-- Named Aura lists are passed by constant, so guard both their contents and
-- their compact sizes in addition to the generic call-table check above.
local auraSource = Read(pagesRoot .. "MSUF_Menu2_Auras.lua")
local auraLists = Slice(auraSource,
    "local function AURA_COOLDOWN_COLOR_REFERENCES",
    "local BUFF_AURA_SORT_METHOD_OK",
    "Aura color reference lists")
assert(Count(auraLists, '"aura.cooldown.') == 4 and Count(auraLists, '"font.global"') == 2,
    "Aura cooldown/duration reference lists no longer contain base + 3 buckets and one duration entry")

-- The compact frame Aura page is the user's primary entry point. Its visible
-- Buff/Debuff and Custom Layout cards must open the same shared Fonts & Colors
-- popup as the deeper Aura Style controls, without adding recurring work.
local auraLayoutContext = Slice(auraSource,
    "function M.AttachAuraFontsAndColors",
    "local BUFF_AURA_SORT_METHOD_OK",
    "Aura Fonts & Colors shortcut")
Has(auraLayoutContext, "local references = AURA_COOLDOWN_COLOR_REFERENCES()",
    "compact Aura layout does not reuse the canonical cooldown color mapping")
Has(auraLayoutContext, "references[2] = AURA_DURATION_BAR_COLOR_REFERENCES[1]",
    "compact Aura layout omits its duration-bar color while timer buckets are disabled")
Has(auraLayoutContext, "W.AttachContextColorReferences(section, references",
    "compact Aura layout has no contextual RGB shortcut")
Has(auraLayoutContext, "textSettings = {",
    "compact Aura layout bypasses the synchronized Fonts & Colors popup")
Has(auraLayoutContext, "colorReferences = references",
    "compact Aura Fonts popup does not expose its matching timer colors")
Has(auraLayoutContext, 'scope = "shared"',
    "compact Aura Fonts popup no longer follows the shared runtime font scope")
for _, forbidden in ipairs({ 'SetScript("OnUpdate"', "RegisterEvent", "RegisterUnitEvent", "C_Timer" }) do
    assert(not auraLayoutContext:find(forbidden, 1, true),
        "compact Aura layout shortcut adds recurring work: " .. forbidden)
end
Has(auraSource, "M.AttachAuraFontsAndColors(section, title, unit)",
    "Buff/Debuff Layout cards have no direct Fonts & Colors entry")
Has(auraSource, 'M.AttachAuraFontsAndColors(section, containerLabel .. " Layout", unit)',
    "Custom Aura Layout cards have no direct Fonts & Colors entry")
Has(auraSource, "M.AttachAuraFontsAndColors(section, title, scope)",
    "Aura Style container selector has no direct Fonts & Colors entry")
assert(Count(auraSource, "AttachAuraFontsAndColors(") == 4,
    "Aura Fonts & Colors shortcuts no longer cover exactly the Style selector and two layout-card paths")
Has(auraLayoutContext, "AURA_SHARED_COLOR_NOTE",
    "Aura Fonts & Colors popup does not disclose its shared color scope")
Has(auraLayoutContext, "colorNote = AURA_SHARED_COLOR_NOTE",
    "Aura shared-scope disclosure is not forwarded to the color picker info button")
Has(auraLayoutContext, 'scopeTag = "Shared"',
    "Aura color picker does not expose its shared scope in the visible picker title")
Has(auraLayoutContext, 'colorScopeTag = "Shared"',
    "Aura text color picker does not retain the visible shared-scope tag")
assert(Count(auraSource, "note = AURA_SHARED_COLOR_NOTE") == 9,
    "not every Aura color shortcut carries the concise shared-scope explanation")
assert(Count(auraSource, 'scopeTag = "Shared"') == 9,
    "not every Aura color shortcut carries the visible Shared tag")

local groupAuraSource = Read(pagesRoot .. "MSUF_Menu2_GroupAuras.lua")
Has(groupAuraSource, 'M.AttachAuraFontsAndColors(top, "Auras", scope)',
    "compact Group Auras workspace has no direct Fonts & Colors entry")

-- Every semantic id used by a feature page must resolve through the canonical
-- registry. Native Dispel colors deliberately have no synthetic picker target.
for id in pairs(referencedIds) do
    Has(registry, '"' .. id .. '"', "page color reference has no registry factory: " .. id)
    assert(not id:lower():find("dispel", 1, true), "native Dispel color was exposed as a fake context reference: " .. id)
end
for factory, id in registry:gmatch('([A-Za-z]+Factory)%s*%(%s*"([a-z_]+%.[a-z0-9_.]+)"') do
    assert(factory and not id:lower():find("dispel", 1, true),
        "semantic registry invents a native Dispel color: " .. id)
end

-- Explicit bounds for mappings assembled incrementally rather than returned as
-- one literal table. These source contracts keep their worst cases at 4/2/3/4.
local unitSections = Read(pagesRoot .. "MSUF_Menu2_UnitSections.lua")
local basics = Slice(unitSections, "local function BuildBasics", "local function BuildLayout", "Unit Frame Basics")
assert(Count(basics, 'refs[#refs + 1] = "bar.background_tint"') == 1,
    "Unit Frame Basics no longer has the bounded 3-gradient + 1-background mapping")

local unitAlpha = Read(pagesRoot .. "MSUF_Menu2_UnitAlpha.lua")
assert(Count(unitAlpha, 'refs[#refs + 1] = "bar.background_tint"') == 1
    and Count(unitAlpha, 'refs[#refs + 1] = "bar.power_background"') == 1,
    "Unit Alpha dynamic mappings are no longer bounded at 4 health / 2 resource colors")

local groupLayout = Read(pagesRoot .. "MSUF_Menu2_GroupLayout.lua")
Has(groupLayout, 'if mode == "GLOBAL" or mode == "CLASS" or mode == "GRADIENT" then',
    "Group Layout omits its effective global/class/gradient foreground colors")
Has(groupLayout, 'references = { "health.current" }',
    "Group Layout does not resolve global/class/gradient through the effective health colors")
Has(groupLayout, 'references = { "group.health" }',
    "Group Layout does not resolve dark/unified/custom through the group health color")
Has(groupLayout, 'if not GroupBackgroundUsesDerivedColor() then',
    "Group Layout exposes an unused custom background while health/class-follow is active")
Has(groupLayout, "classToken = GROUP_HEALTH_PREVIEW_CLASS[scope]",
    "Group Layout class color has no deterministic preview context")
Has(groupLayout, 'CurrentGroupEffectiveHealthMode() ~= "GRADIENT"',
    "Group Layout can overflow three gradient stops plus background with a fifth dead color")

local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
Has(groupConfig,
    'dst.healA = Clamp01(scopedValue(conf, general, "healPredictionBarOpacity", general and general.healPredictionColorA), 0.45)',
    "Group heal prediction ignores the selected Bars-scope opacity")

local unitVisuals = Read(pagesRoot .. "MSUF_Menu2_UnitFrameVisuals.lua")
Has(unitVisuals, 'W.AttachContextColorReferences(borderCard, { "portrait.border" },',
    "Portrait Shape & Border card does not keep its RGB shortcut available for pre-configuration")
Has(unitVisuals, 'W.AttachContextColorReferences(styleCard, { "portrait.background" },',
    "Portrait Class & Background card does not keep its RGB shortcut available for pre-configuration")
local castbarCards = Slice(unitVisuals, "local function GeneralCastbarColorRefs", "local castbarTabs", "unit castbar cards")
assert(Count(castbarCards, 'refs[#refs + 1] = "cast.interrupt_feedback"') == 1,
    "unit castbar dynamic mapping is no longer bounded at three colors")
Has(castbarCards, "local function IconBorderColorRefs()",
    "unit castbar icon cards do not filter their color by the selected style")
Has(castbarCards, 'return style == "CASTBAR" and { "cast.border" } or {}',
    "unit castbar icon cards expose a color for hardcoded Dark/None styles")
Has(unitVisuals, "if M.Refresh then M.Refresh(ctx) end",
    "unit castbar icon color relevance does not refresh after a style change")

local globalCastbars = Read(pagesRoot .. "MSUF_Menu2_GlobalCastbars.lua")
Has(globalCastbars, "capabilities = { baseline = false }",
    "global Cast Text popup exposes an unsupported baseline control")
Has(globalCastbars, "capabilities = { shadow = false, opacity = false, baseline = false }",
    "Focus Kick popup exposes font controls its runtime does not consume")

local globalBars = Read(pagesRoot .. "MSUF_Menu2_GlobalBars.lua")
Has(globalBars, "local function AttachBarsColorShortcut",
    "Bars has no color-popup-only target helper")
Has(globalBars, "local function CaptureBarsScopeFields",
    "Bars color popups do not capture their scoped structural DB state")
Has(globalBars, "local function RestoreBarsScopeFields",
    "Bars color popups cannot restore scoped structural DB state on cancel")
Has(globalBars, "TEMP_MAX_HEALTH_COLOR_STATE_FIELDS",
    "Maximum Health Loss color popup does not preserve override and field presence")
Has(globalBars, "OUTLINE_COLOR_STATE_FIELDS",
    "Frame Outline color popup does not preserve mode, override, and field presence")
Has(globalBars, '"Maximum Health Loss Color"',
    "Maximum Health Loss no longer exposes its color through the popup")
Has(globalBars, '"Frame Outline Color"',
    "Frame Outline no longer exposes its color through the popup")
assert(not globalBars:find('W.Color(section, "Loss color")', 1, true),
    "Maximum Health Loss still duplicates its color inside the normal Bars controls")
assert(not globalBars:find('W.Color(outline, "Outline color")', 1, true),
    "Frame Outline still duplicates its color inside the normal Bars controls")
Has(globalBars, 'local opacityY = compact and -204 or -78',
    "compact Maximum Health Loss layout still reserves the removed color row")

local classPower = Slice(registry,
    'ContextFactory("class_power.current"',
    'ContextGradientFactory("gradient.health"',
    "dynamic class-power factory")
assert(Count(classPower, "targets[#targets + 1] = ClassPowerTarget") == 2,
    "class-power dynamic mapping is no longer bounded at four colors")
Has(colors, "MANA=Alternative Mana", "Colors menu does not expose the Alternative Mana runtime source")
Has(classPower, 'ContextTarget("class_power.alt_mana", "Alternative mana"',
    "Alternative Mana card does not resolve its effective Class Power color")
Has(classPower, 'GetClassPowerRGB("MANA")',
    "Alternative Mana popup does not read the visible runtime color")
Has(colors, 'MANA RESOURCE_TEXT]])',
    "Alternative Mana is missing from the exact class-power color metadata")

local auras = Read(pagesRoot .. "MSUF_Menu2_Auras.lua")
assert(Count(auras, 'scope = "shared"') >= 5,
    "Aura stack/cooldown text popups no longer follow the shared Fonts scope")
Has(auras, "shadowAlpha = false", "Aura text popup exposes an unsupported shadow-opacity control")
Has(auras, "shadowDistance = false", "Aura text popup exposes an unsupported shadow-distance control")

-- Aura duration bars share the Safe timer color in live frames and every
-- preview. Fill direction changes progress only; it must not invent cyan/green.
local auraModel = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
Has(auraModel, "function Model.GetDurationBarColor()",
    "Auras3 has no shared duration-bar color source")
Has(auraModel, "A3.GetDurationBarColor = Model.GetDurationBarColor",
    "Auras3 does not publish its duration-bar color to runtime/previews")
Has(auraModel, "MSUF_GetConfiguredFontColor",
    "Aura duration-bar color does not inherit the configured font color when Safe is unset")
local auraColorConsumers = {
    Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"),
    Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua"),
    Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua"),
    Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua"),
    Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua"),
    auras,
}
for _, source in ipairs(auraColorConsumers) do
    Has(source, "GetDurationBarColor", "an aura duration-bar surface bypasses the shared Safe color")
    assert(not source:find("SetVertexColor(0.08, 0.78", 1, true)
        and not source:find("SetVertexColor(0.22, 0.88", 1, true),
        "an aura preview still hardcodes direction-specific duration-bar colors")
end
local auraColorsPage = Slice(colors,
    "local function BuildAuraAndPortraitColors",
    "local function OpenFontsTextColors",
    "visible Aura colors page")
Has(auraColorsPage, 'Card(auras, "Timer Thresholds"',
    "Aura Colors does not present its actual timer-threshold controls")
assert(not auraColorsPage:find("AuraColorAt(markers", 1, true)
    and not auraColorsPage:find("ColorValueAt(ctx, markers", 1, true),
    "Aura Colors still exposes stored values with no Auras3 runtime consumer")
Has(auraColorsPage, "GetAuraSafeRGB",
    "Aura Colors Safe swatch does not show its effective inherited font color")
local fontFactory = Slice(registry,
    'FixedContextFactory("font.global"',
    'ContextFactory("font.default.current"',
    "global font color factory")
Has(fontFactory, "M._ContextConfiguredGlobalFontRGB",
    "global-font RGB picker previews white instead of the selected Fonts palette color")
local auraFactory = Slice(registry,
    "local function AuraTableFactory",
    'FixedContextFactory("group.health"',
    "Aura semantic color factories")
Has(auraFactory, 'ContextTarget("aura.cooldown.safe", "Cooldown safe", M._ContextGetAuraSafeRGB, M._ContextSetAuraSafeRGB)',
    "Aura Safe popup does not share the effective Colors/runtime source")

local unitStatus = Read(pagesRoot .. "MSUF_Menu2_UnitStatusSection.lua")
Has(unitStatus, "W.AttachContextColorShortcut(selectedCard",
    "Unit status text has no contextual Fonts & Colors popup")
Has(unitStatus, 'kind = "status"', "Unit status popup does not identify its runtime text kind")
local groupIndicators = Read(pagesRoot .. "MSUF_Menu2_GroupIndicators.lua")
Has(groupIndicators, "W.AttachContextColorShortcut(groupNumberCard",
    "Group Number text has no contextual Fonts & Colors popup")
Has(groupIndicators, "W.AttachContextColorShortcut(selectedCard",
    "Group status text has no contextual Fonts & Colors popup")

print("context_color_cross_reference_smoke: ok")
