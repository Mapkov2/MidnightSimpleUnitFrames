local unpack = table.unpack or unpack

local function Words(value)
    local result = {}
    for word in tostring(value or ""):gmatch("%S+") do result[#result + 1] = word end
    return result
end

local function ColorRows(value)
    local result = {}
    for encoded in tostring(value or ""):gmatch("[^;]+") do
        local fields = {}
        for field in encoded:gmatch("[^|]+") do fields[#fields + 1] = field end
        result[#result + 1] = {
            key = fields[1], label = fields[2],
            dr = tonumber(fields[3]), dg = tonumber(fields[4]), db = tonumber(fields[5]),
        }
    end
    return result
end

local registeredPage
local M = {
    AdvancedPage = {},
    Theme = {
        colors = { text = { 1, 1, 1, 1 }, muted = { 0.5, 0.5, 0.5, 1 } },
        Font = function() return { SetPoint = function() end, SetText = function() end } end,
    },
    Widgets = { SetControlsEnabled = function() end },
    KeyLabelRows = function() return {} end,
    WordList = Words,
    ColorRows = ColorRows,
    KeyLabelMap = function() return {} end,
    ValueTextPairs = function() return {} end,
}
function M.Pick(source, names)
    local values, count = {}, 0
    for name in names:gmatch("%S+") do
        count = count + 1
        values[count] = source[name]
    end
    return unpack(values, 1, count)
end
function M.RegisterPage(key, page)
    assert(key == "opt_colors", "unexpected page key: " .. tostring(key))
    registeredPage = page
end

local MSUF = { MSUF2 = M }
local path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
assert(registeredPage and type(registeredPage.build) == "function", "colors page was not registered")
assert(registeredPage.version == 19, "colors page version changed")

local upvalues, categoryBuilders, index = 0, nil, 1
while true do
    local name, value = debug.getupvalue(registeredPage.build, index)
    if not name then break end
    if name == "COLOR_CATEGORY_BUILDERS" then categoryBuilders = value end
    upvalues, index = upvalues + 1, index + 1
end
assert(upvalues <= 40, "BuildColors exceeds the upvalue budget: " .. upvalues)
assert(type(categoryBuilders) == "table", "BuildColors lost its category builders")
for _, categoryKey in ipairs({ "unit", "group", "cast", "auras", "resources" }) do
    assert(type(categoryBuilders[categoryKey]) == "function", "missing category builder: " .. categoryKey)
end

local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local components = {
    "BuildFontAndClassColors", "BuildBackgroundAndAppearance", "BuildUnitAndNPCColors",
    "BuildBarAndGroupColors", "BuildCastbarColors", "BuildHighlightAndGameplayColors",
    "BuildPowerAndClassPowerColors", "BuildAuraAndPortraitColors",
}
for _, name in ipairs(components) do
    assert(source:find("local function " .. name, 1, true), "missing color-domain builder: " .. name)
end
local buildersCursor = assert(source:find("local COLOR_CATEGORY_BUILDERS", 1, true))
local buildersSource = source:sub(buildersCursor)
for _, name in ipairs(components) do
    assert(buildersSource:find(name .. "(ctx, inner", 1, true), "missing color-domain build call: " .. name)
end
assert(not source:find('stateKey = "colorsGroupFrameTab"', 1, true), "Group Frame colors should use accordions, not tabs")
assert(source:find("local function PendingColorFocusCategory", 1, true), "categories lost search/deep-link aware lazy building")
assert(source:find("if ctx.hiddenBuild then", 1, true), "hidden (coverage) builds no longer materialize every category")
assert(source:find("_msuf2ResolveMissingSection", 1, true), "cross-page focus requests can no longer materialize lazy categories")
assert(source:find("_msuf2EnsureVisible", 1, true), "focused sections can no longer reveal their category")
assert(not source:find("if activeKey ~= categoryKey then", 1, true),
    "same-category activation can leave the active color settings container hidden")
assert(not source:find("local categorySpecs = {}", 1, true)
    and source:find("topInset = 0", 1, true),
    "Color settings still insert a redundant category headline between navigation and controls")
assert(source:find("for i = count + 1, #slotControls do W.SetControlShown(slotControls[i], false) end", 1, true), "class-power slot visibility lost its initial delta path")
assert(not source:find("M.TrackRefresh(ctx, RefreshSlotControls)\n    RefreshSlotControls()", 1, true), "class-power slot visibility refresh runs twice during page build")
local widgetsFile = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua", "rb"))
local widgetsSource = widgetsFile:read("*a")
widgetsFile:close()
local bindingsFile = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua", "rb"))
local bindingsSource = bindingsFile:read("*a")
bindingsFile:close()
assert(widgetsSource:find("AttachBoundColorToCollapsible", 1, true), "missing automatic accordion color swatches")
assert(bindingsSource:find("widgets.AttachBoundColorToCollapsible", 1, true), "color bindings do not attach header swatches")

local sections = {
    "colors_font", "colors_classes", "colors_background", "colors_appearance", "colors_unit",
    "colors_npc_type", "colors_bar_colors", "colors_bar_gradients", "colors_group_frames",
    "colors_group_frames_background", "colors_group_frames_state", "colors_group_frames_highlights",
    "colors_castbar", "colors_highlight", "colors_gameplay", "colors_power", "colors_class_power",
    "colors_auras", "colors_portrait",
}
for _, key in ipairs(sections) do
    assert(source:find('CollapsibleSection("' .. key .. '"', 1, true), "missing section: " .. key)
    assert(source:find('"' .. key .. '"', source:find("local COLOR_CATEGORY_SECTIONS", 1, true), true),
        "section is not mapped to a painter category: " .. key)
end

local settingContracts = {
    -- Class, NPC, power, class-power and combo-slot palettes.
    "COLOR_CLASS_TOKENS", "COLOR_NPC_ROWS", "COLOR_NPC_TYPE_ROWS", "COLOR_POWER_TOKENS",
    "COLOR_CP_TOKENS", "COLOR_CP_SLOT_TOKENS", "classPowerComboPointColorMode",
    -- Auras, portraits, group frames, castbars and gameplay/highlight colors.
    "aurasCooldownTextSafeColor", "aurasCooldownTextWarningColor", "aurasCooldownTextUrgentColor",
    "aurasStackCountColor", "aurasOwnBuffHighlightColor", "aurasOwnDebuffHighlightColor",
    "portraitBorderColor", "portraitBgColor", "gfBarMode",
    "playerCastbarOverride", "kickReadyColor", "kickNotReadyColor", "highlightColor",
    "bossTargetHighlightColor", "combatTimerColor", "combatStateEnterColor", "combatStateLeaveColor",
    "crosshairInRangeColor", "crosshairOutRangeColor",
}
for _, token in ipairs(settingContracts) do
    assert(source:find(token, 1, true), "missing color setting contract: " .. token)
end

local applyContracts = {
    "RequestColors", "RequestGeneral", "RequestClassPower", "RequestAuraFonts", "RequestGroup",
    "RequestBossTargetBorder", "MSUF_GF_ForceAuraTextColorRefresh", "MSUF_ClassPower_InvalidateColors",
    "MSUF_UFCore_NotifyConfigChanged", "MSUF_UFPreview_RequestRefresh",
}
for _, token in ipairs(applyContracts) do
    assert(source:find(token, 1, true), "missing runtime apply route: " .. token)
end

local resetContracts = {
    "ResetGlobalFontToPalette", "ResetAllClassColors", "ResetAllNPCColors", "ResetNPCTypeColors",
    "ResetPowerOverride", "ResetClassPowerRGB", "ResetAuraColorSettings",
    '"unitframe.reset"', '"npc_type.reset"', '"castbar.reset"', '"gameplay.reset"', '"portrait.reset"',
}
for _, token in ipairs(resetContracts) do
    assert(source:find(token, 1, true), "missing reset contract: " .. token)
end

assert(source:find('ControlMeta("opt_colors", "advanced"', 1, true), "page ControlMeta scope changed")
assert(source:find("RegisterControl(btn, Meta(semanticPath", 1, true), "button metadata registration was lost")
assert(source:find("M.BindColor(ctx, color, getRGB, setRGB, metadata)", 1, true), "color metadata binding was lost")

-- Behavior harness: run the real BuildColors with the category builders
-- swapped for counting stubs, so category laziness, hidden (coverage) builds
-- and deep-link materialization stay pinned without the widget stack.
local CATEGORY_TEST_SECTIONS = {
    unit = { "colors_appearance" },
    group = { "colors_group_frames" },
    cast = { "colors_castbar" },
    auras = { "colors_auras" },
    resources = { "colors_power" },
}

local function NewMockFrame()
    local frame = { shown = true, height = 60 }
    function frame:SetSize(_, height) self.height = height end
    function frame:SetHeight(height) self.height = height end
    function frame:GetHeight() return self.height end
    function frame:SetPoint() end
    function frame:SetShown(shown) self.shown = shown and true or false end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    return frame
end

local function RunBuildColorsHarness(opts)
    opts = opts or {}
    local previousCreateFrame = _G.CreateFrame
    _G.CreateFrame = NewMockFrame
    local buildCounts = {}
    local testBuilders = {}
    for categoryKey in pairs(categoryBuilders) do
        testBuilders[categoryKey] = function(builderCtx, inner)
            buildCounts[categoryKey] = (buildCounts[categoryKey] or 0) + 1
            for _, sectionId in ipairs(CATEGORY_TEST_SECTIONS[categoryKey] or {}) do
                builderCtx.entry.sections[sectionId] = { _msuf2SectionId = sectionId }
                inner.collapsibles[#inner.collapsibles + 1] = { sectionId = sectionId }
            end
        end
    end
    local builderUpvalue
    for i = 1, upvalues do
        local name = debug.getupvalue(registeredPage.build, i)
        if name == "COLOR_CATEGORY_BUILDERS" then builderUpvalue = i break end
    end
    assert(builderUpvalue, "COLOR_CATEGORY_BUILDERS upvalue not found")
    debug.setupvalue(registeredPage.build, builderUpvalue, testBuilders)
    M.Widgets.PageBuilder = function(_, builderOpts)
        if not builderOpts then
            local b = {
                x = 12, y = -12, width = 720, parent = "root",
                layoutEntries = {}, collapsibles = {},
            }
            function b:GlobalStyleHeader() self.y = self.y - 84 end
            function b:RequestRelayoutCollapsibles() self._msuf2RelayoutPending = true end
            function b:RelayoutCollapsibles() self._msuf2RelayoutPending = nil end
            return b
        end
        local inner = { collapsibles = {} }
        function inner:RelayoutCollapsibles() builderOpts.onContentHeight(240) end
        return inner
    end
    local ctx = {
        key = "opt_colors",
        hiddenBuild = opts.hiddenBuild == true,
        entry = { sections = {} },
        refreshers = {},
        width = 720,
    }
    function ctx:SetContentHeight() end
    M.colorsPainterCategory = opts.painterCategory
    local ok, err = pcall(registeredPage.build, ctx)
    -- Keep the stub builders installed: the installed callbacks
    -- (M.ColorsEnsureCategoryBuilt, resolver) share the upvalue cell and are
    -- exercised after the build returns. Restored once at the end of the file.
    _G.CreateFrame = previousCreateFrame
    assert(ok, "BuildColors harness failed: " .. tostring(err))
    return ctx, buildCounts, builderUpvalue
end

do
    local ctx, buildCounts = RunBuildColorsHarness({ painterCategory = "unit" })
    assert(buildCounts.unit == 1, "active category was not built exactly once")
    assert(not buildCounts.cast and not buildCounts.auras and not buildCounts.resources and not buildCounts.group,
        "inactive categories were built eagerly")
    assert(type(M.ColorsOnPainterCategory) == "function", "painter tab callback was not installed")
    assert(type(M.ColorsEnsureCategoryBuilt) == "function", "paint popover cannot materialize categories")
    M.ColorsEnsureCategoryBuilt("colors_castbar")
    assert(buildCounts.cast == 1, "M.ColorsEnsureCategoryBuilt did not build the owning category")
    assert(type(ctx.entry._msuf2ResolveMissingSection) == "function", "missing-section resolver was not installed")
    local resolved = ctx.entry._msuf2ResolveMissingSection("colors_auras")
    assert(buildCounts.auras == 1 and resolved and resolved._msuf2SectionId == "colors_auras",
        "deep-linked section did not materialize its category")
    M.ColorsOnPainterCategory("group")
    assert(buildCounts.group == 1, "tab switch did not build its category")
end

do
    local _, buildCounts = RunBuildColorsHarness({ hiddenBuild = true })
    for _, categoryKey in ipairs({ "unit", "group", "cast", "auras", "resources" }) do
        assert(buildCounts[categoryKey] == 1, "hidden (coverage) build skipped category: " .. categoryKey)
    end
end

do
    local previous = _G.MSUF_EM2_MenuFocusRequest
    _G.MSUF_EM2_MenuFocusRequest = { explicit = true, pageKey = "opt_colors", sectionId = "colors_castbar" }
    local _, buildCounts = RunBuildColorsHarness()
    _G.MSUF_EM2_MenuFocusRequest = previous
    assert(buildCounts.cast == 1, "deep-linked category remained unbuilt")
end

M.ColorsOnPainterCategory = nil
M.ColorsEnsureCategoryBuilt = nil
for i = 1, upvalues do
    local name = debug.getupvalue(registeredPage.build, i)
    if name == "COLOR_CATEGORY_BUILDERS" then
        debug.setupvalue(registeredPage.build, i, categoryBuilders)
        break
    end
end

print("advanced colors page contract smoke: ok (BuildColors upvalues=" .. upvalues .. ")")
