-- Exercise native renderers: native FontStrings do not translate their SetText input.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Check(ok, message) assert(ok, "locale_render_paths: " .. message) end
local function Find(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
        if type(value) == "function" then
            local found = Find(value, wanted, seen)
            if found then return found end
        end
    end
end
local mw = MenuWorld.Open(root, "Mainline", { locale = "deDE", open = false })
local core, env, M = mw.core, mw.env, mw.M
core.FinalizeLocale()
local native = env.UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
native:SetText("Boss Preview")
Check(native:GetText() == "Boss Preview", "fixture font translates on its own")
local boss = assert(Find(core.UF.ApplyBossPreviewState, "ApplyBossPreviewText"), "boss renderer missing")
boss({ nameText = native }, 55, 100, 100, 100)
Check(native:GetText() == core.Translate("Boss Preview") and native:GetText() ~= "Boss Preview", "boss label stays English")
local arena = assert(Find(core.UF.ApplyArenaPreviewState, "ApplyArenaPreviewText"), "arena renderer missing")
env.LOCALIZED_CLASS_NAMES_MALE = {}
arena({ nameText = native }, 55, 100, 100, 100, "UNKNOWN")
Check(native:GetText() == core.Translate("Arena Preview") and native:GetText() ~= "Arena Preview", "arena fallback stays English")
env.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Client class name" }
arena({ nameText = native }, 55, 100, 100, 100, "MAGE")
Check(native:GetText() == "Client class name", "native localized class name was replaced")
local default = assert(Find(core.MSUF_ApplyGameplayVisuals, "TextOrDefault"), "combat text resolver missing")
for _, token in ipairs({ "+Combat", "-Combat" }) do
    for _, value in ipairs({ false, "", token }) do
        Check(default(value, token) == core.Translate(token), "default combat cue stays English")
    end
end
for _, custom in ipairs({ "Ready!", "Custom Kampf", "Boss Preview" }) do
    Check(default(custom, "+Combat") == custom, "custom combat cue was translated")
end
env.MSUF_DB.general.showBossCastTargetName = true
M.Open("opt_castbar")
mw:RunTimers()
local target = core.Translate("Cleave Training Dummy")
M.SetCastbarPreviewUnit("boss")
local castPreview = assert(M._msuf2CastbarPreview, "castbar preview missing")
castPreview:Refresh()
mw:RunTimers()
Check(castPreview.castTargetText:GetText() == target, "cast target preview does not paint its localized sample")
core.SuiteLink.HasColorsCategory = function() return true end
core.SuiteLink.BuildColorsCategory = function() end
M.colorsPainterCategory = "suite"
M.Open("opt_colors")
mw:RunTimers()
local noteKey = "Suite colors are in the sections below.\nOpen the Minimap preview to position its elements."
Check(core.Translate(noteKey) ~= noteKey, "Suite color hint lacks its German translation")
M.ColorsSetPainterCategory("suite")
mw:RunTimers()
local found = false
for _, frame in ipairs(mw.world.widgets.frames) do
    for _, region in ipairs(frame.regions or {}) do
        if region.GetText and region:GetText() == core.Translate(noteKey) then found = true end
    end
end
Check(found, "native Suite color hint stays English")
Check(core.Translate("|cff6EB5FFIcons|r") == "|cff6EB5FFSymbole|r", "icon heading stays English")
local routeKeys = {
    "Open that unit page and use Frame Basics for width, height, and scale. Text size is in Style > Fonts or the unit Text section.",
    "Use the unit page for per-unit castbar toggles and Frames > Cast Bars for shared textures, direction, text, and interrupt options.",
    "Boss frames normally appear only during boss encounters. Enable Boss Frames and use Edit Mode or Boss Preview to test them outside combat.",
    "Open Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar Colors controls class overrides.",
    "Use Dashboard > Reset Positions for frame movers. Use Profiles only when you want to reset, copy, import, or replace profile data.",
    "Open Frames > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.",
    "Absorb styling and heal prediction are in Frames > Bars > Absorb Display. Use the Party or Raid scope there for group incoming heals.",
    "Open the matching unit page and check Frame Basics > Enable, Load Conditions, alpha/transparency, and range fade.",
    "Open Frames > Party/Raid Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode, frame scaling, and anchoring.",
    "Open Frames > Party/Raid Frames > Status & Indicators for status icons, role/leader/assist, ready check, focus glow, and other group-frame state indicators.",
}
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local ns = {}
    _G.GetLocale = function() return locale end
    _G.CreateFrame = nil
    _G.MSUF_NS, _G.MSUF = ns, ns
    local dir = root .. "/MidnightSimpleUnitFrames/Locales/"
    assert(loadfile(dir .. "MSUF_Localization.lua"))("MidnightSimpleUnitFrames", ns)
    assert(loadfile(dir .. locale .. ".lua"))("MidnightSimpleUnitFrames", ns)
    ns.FinalizeLocale()
    for _, key in ipairs({ noteKey, "Arena Preview", "Boss Preview", "+Combat", "-Combat" }) do
        local sameWord = locale == "frFR" and (key == "+Combat" or key == "-Combat")
        Check(rawget(ns.L, key) ~= nil and (sameWord or ns.Translate(key) ~= key), locale .. " missing " .. key)
    end
    for _, key in ipairs(routeKeys) do
        local translated = ns.Translate(key)
        for _, fragment in ipairs({ "Frame Basics", "Style > Fonts", "Bar Colors", "Frame Outline", "Highlight Borders", "Party/Raid Frames", "Frames >", "Boss Frames", "Absorb Display", "Status & Indicators" }) do
            Check(not translated:find(fragment, 1, true), locale .. " keeps English route fragment " .. fragment)
        end
    end
end
print("locale_render_paths_smoke: OK (native previews, defaults and custom combat text)")
