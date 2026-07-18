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
assert(registeredPage.version == 12, "colors page version changed")

local upvalues, index = 0, 1
while debug.getupvalue(registeredPage.build, index) do
    upvalues, index = upvalues + 1, index + 1
end
assert(upvalues <= 40, "BuildColors exceeds the upvalue budget: " .. upvalues)

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
local cursor = assert(source:find("local function BuildColors(ctx)", 1, true))
for _, name in ipairs(components) do
    local call = name .. "(ctx, b, CH)"
    cursor = assert(source:find(call, cursor, true), "color-domain order changed: " .. name) + #call
end

local sections = {
    "colors_font", "colors_classes", "colors_background", "colors_appearance", "colors_unit",
    "colors_npc_type", "colors_bar_colors", "colors_group_frames", "colors_castbar",
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

print("advanced colors page contract smoke: ok (BuildColors upvalues=" .. upvalues .. ")")
