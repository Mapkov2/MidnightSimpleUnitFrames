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
    AdvancedPage = {}, Theme = {}, Widgets = { SetControlsEnabled = function() end },
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
local path = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
assert(registeredPage and type(registeredPage.build) == "function", "colors page was not registered")
assert(registeredPage.version == 18, "colors page version changed")

local upvalues, buildColorGroup, index = 0, nil, 1
while true do
    local name, value = debug.getupvalue(registeredPage.build, index)
    if not name then break end
    if name == "BuildColorGroup" then buildColorGroup = value end
    upvalues, index = upvalues + 1, index + 1
end
assert(upvalues <= 40, "BuildColors exceeds the upvalue budget: " .. upvalues)
assert(type(buildColorGroup) == "function", "BuildColors lost its color-group builder")

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
local buildCursor = assert(source:find("local function BuildColors(ctx)", 1, true))
local buildSource = source:sub(buildCursor)
for _, name in ipairs(components) do
    assert(buildSource:find(name .. "(ctx, ", 1, true), "missing color-domain build call: " .. name)
end
for _, id in ipairs({ "colors_group_general", "colors_group_units", "colors_group_groups", "colors_group_bars", "colors_group_additional" }) do
    assert(buildSource:find('"' .. id .. '"', 1, true), "missing color group: " .. id)
end
assert(not source:find('stateKey = "colorsGroupFrameTab"', 1, true), "Group Frame colors should use accordions, not tabs")
assert(source:find("local function ColorGroupHasPendingFocus", 1, true), "color groups lost search/deep-link aware lazy building")
assert(source:find("if (ctx and ctx.hiddenBuild) or entry.open or ColorGroupHasPendingFocus", 1, true), "collapsed color groups are built eagerly")
assert(source:find("entry._msuf2RefreshState = RefreshLazyGroup", 1, true), "collapsed color groups do not build on first open")
assert(source:find("for i = count + 1, #slotControls do W.SetControlShown(slotControls[i], false) end", 1, true), "class-power slot visibility lost its initial delta path")
assert(not source:find("M.TrackRefresh(ctx, RefreshSlotControls)\n    RefreshSlotControls()", 1, true), "class-power slot visibility refresh runs twice during page build")
local widgetsFile = assert(io.open("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua", "rb"))
local widgetsSource = widgetsFile:read("*a")
widgetsFile:close()
local bindingsFile = assert(io.open("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua", "rb"))
local bindingsSource = bindingsFile:read("*a")
bindingsFile:close()
assert(widgetsSource:find("AttachBoundColorToCollapsible", 1, true), "missing automatic accordion color swatches")
assert(bindingsSource:find("widgets.AttachBoundColorToCollapsible", 1, true), "color bindings do not attach header swatches")

local sections = {
    "colors_font", "colors_classes", "colors_background", "colors_appearance", "colors_unit",
    "colors_npc_type", "colors_bar_colors", "colors_group_frames", "colors_group_frames_background",
    "colors_group_frames_state", "colors_group_frames_highlights", "colors_castbar",
    "colors_highlight", "colors_gameplay", "colors_power", "colors_class_power",
    "colors_auras", "colors_portrait",
}
for _, key in ipairs(sections) do
    assert(source:find('CollapsibleSection("' .. key .. '"', 1, true), "missing section: " .. key)
end

local settingContracts = {
    -- Class, NPC, power, class-power and combo-slot palettes.
    "COLOR_CLASS_TOKENS", "COLOR_NPC_ROWS", "COLOR_NPC_TYPE_ROWS", "COLOR_POWER_TOKENS",
    "COLOR_CP_TOKENS", "COLOR_CP_SLOT_TOKENS", "classPowerComboPointColorMode",
    -- Auras, portraits, group frames, castbars and gameplay/highlight colors.
    "aurasCooldownTextSafeColor", "aurasCooldownTextWarningColor", "aurasCooldownTextUrgentColor",
    "aurasStackCountColor", "aurasOwnBuffHighlightColor", "aurasOwnDebuffHighlightColor",
    "portraitBorderColor", "portraitBgColor", "gfBarMode",
    "playerCastbarOverride", "kickReadyColor", "kickNotReadyColor", "highlightEnabled",
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

local function NewLazyHarness(opts)
    opts = opts or {}
    local entry = {}
    entry.open = opts.open == true
    entry.headerHeight = 36
    entry.contentHeight = 96
    entry.body = { SetHeight = function(_, height) entry.bodyHeight = height end }
    entry.outer = { SetHeight = function(_, height) entry.outerHeight = height end }
    local group = { _msuf2CollapsibleEntry = entry, _msuf2Width = 720 }
    local root = {
        CollapsibleSection = function() return group end,
        RequestRelayoutCollapsibles = function(self) self._msuf2RelayoutPending = true end,
    }
    local ctx = {
        key = "opt_colors",
        hiddenBuild = opts.hiddenBuild == true,
        entry = {},
        refreshers = {},
        width = 720,
    }
    local innerRelayouts = 0
    M.Widgets.PageBuilder = function(_, builderOpts)
        return {
            RelayoutCollapsibles = function()
                innerRelayouts = innerRelayouts + 1
                builderOpts.onContentHeight(180)
            end,
        }
    end
    return ctx, root, entry, function() return innerRelayouts end
end

do
    local ctx, root, entry, InnerRelayouts = NewLazyHarness()
    local builds, refreshes = 0, 0
    buildColorGroup(ctx, root, "colors_group_test", "Test", nil, false, { "colors_child" }, function()
        builds = builds + 1
        ctx.refreshers[#ctx.refreshers + 1] = function() refreshes = refreshes + 1 end
    end)
    assert(builds == 0 and type(entry._msuf2RefreshState) == "function", "closed color group was not left lazy")
    entry.open = true
    entry._msuf2RefreshState()
    assert(builds == 1 and refreshes == 1, "first color-group open did not build and refresh exactly once")
    assert(InnerRelayouts() == 1 and entry.bodyHeight == 180 and entry.outerHeight == 216, "lazy color-group height did not settle")
    assert(root._msuf2RelayoutPending == nil, "lazy color-group left a redundant root relayout queued")
    entry._msuf2RefreshState()
    assert(builds == 1 and refreshes == 1, "lazy color group rebuilt during a later refresh")
end

do
    local ctx, root = NewLazyHarness({ hiddenBuild = true })
    local builds = 0
    buildColorGroup(ctx, root, "colors_group_hidden", "Hidden", nil, false, { "colors_hidden_child" }, function()
        builds = builds + 1
    end)
    assert(builds == 1, "hidden search build no longer registers nested color controls")
end

do
    local previous = _G.MSUF_EM2_MenuFocusRequest
    _G.MSUF_EM2_MenuFocusRequest = { explicit = true, pageKey = "opt_colors", sectionId = "colors_focus_child" }
    local ctx, root = NewLazyHarness()
    local builds = 0
    buildColorGroup(ctx, root, "colors_group_focus", "Focus", nil, false, { "colors_focus_child" }, function()
        builds = builds + 1
    end)
    _G.MSUF_EM2_MenuFocusRequest = previous
    assert(builds == 1, "deep-linked color group remained unbuilt")
end

print("advanced colors page contract smoke: ok (BuildColors upvalues=" .. upvalues .. ")")
