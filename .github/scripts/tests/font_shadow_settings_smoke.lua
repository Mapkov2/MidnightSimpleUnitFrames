local root = arg[1] or "."

local function Read(relative)
    local path = root .. "/" .. relative
    local file = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"))
end

local function Equal(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local defaults = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
local resolverSource = assert(defaults:match("(local function MSUF_ResolveFontShadowMetrics.-)\nend\nExportPublic"),
    "shadow resolver source missing")
resolverSource = resolverSource:gsub("^local function MSUF_ResolveFontShadowMetrics", "return function", 1) .. "\nend"
local resolver = assert((loadstring or load)(resolverSource, "shadow-resolver"))()

local alpha, x, y = resolver(nil, nil, "SOFT")
Equal(alpha, 0.55, "legacy soft opacity")
Equal(x, 1, "legacy soft distance")
Equal(y, -1, "legacy soft y")

alpha, x, y = resolver(nil, nil, "DEEP")
Equal(alpha, 1, "legacy deep opacity")
Equal(x, 2, "legacy deep distance")
Equal(y, -2, "legacy deep y")

alpha, x, y = resolver(0.73, 1.4)
Equal(alpha, 0.73, "custom opacity")
Equal(x, 1, "rounded distance")
Equal(y, -1, "rounded y")

alpha, x, y = resolver(0.01, 9)
Equal(alpha, 0.20, "minimum opacity")
Equal(x, 2, "maximum distance")
Equal(y, -2, "maximum y")

alpha, x, y = resolver(nil, nil, nil, 0.65, 2)
Equal(alpha, 0.65, "scope opacity fallback")
Equal(x, 2, "scope distance fallback")
Equal(y, -2, "scope y fallback")

assert(defaults:find("scope.fontShadowStrength = nil", 1, true), "legacy preset migration missing")
assert(defaults:find("MSUF_Defaults_NormalizeFontShadowScope(g, true)", 1, true), "global normalization missing")

local menu = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua")
assert(menu:find('W.Slider(text, "Shadow opacity", 0.20, 1, 0.05, 300)', 1, true), "opacity slider missing")
assert(menu:find('BindTextSegment("Shadow distance", VT(1, "1 px", 2, "2 px")', 1, true), "distance segment missing")
assert(menu:find("SetControlEnabled(shadowOpacity, shadowEnabled)", 1, true), "opacity disabled-state missing")
assert(menu:find("SetControlEnabled(shadowDistance, shadowEnabled)", 1, true), "distance disabled-state missing")
assert(menu:find("SHADOW_OPACITY_APPLY_DELAY = 0.18", 1, true), "opacity apply debounce missing")
assert(menu:find('ScopeWrite(CurrentFontScope(), "fontOverride", G(), key, value)', 1, true),
    "opacity drag still uses the applying scope writer")
assert(menu:find("if shadowOpacity._msuf2SliderActive then return end", 1, true),
    "opacity drag does not suppress runtime refreshes")
assert(menu:find('shadowOpacity:HookScript("OnMouseUp", FlushShadowOpacityApply)', 1, true),
    "opacity drag does not flush on release")
assert(menu:find("history = false", 1, true), "debounced opacity apply creates an extra history checkpoint")

local unitConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua")
assert(unitConfig:find("out.fontShadowAlpha = shadowAlpha", 1, true), "unit shadow alpha is not compiled")
assert(unitConfig:find("out.fontShadowX = shadowX", 1, true), "unit shadow distance is not compiled")

local textRuntime = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua")
assert(not textRuntime:find("fontShadowOpacity", 1, true), "unit text hotpath reads shadow opacity")
assert(not textRuntime:find("fontShadowDistance", 1, true), "unit text hotpath reads shadow distance")

print("font_shadow_settings_smoke: ok")
