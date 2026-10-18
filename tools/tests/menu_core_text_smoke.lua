-- menu_core_text_smoke.lua <repoRoot> <flavor> [parentWindowPath]
--
-- Text and chrome contracts of the Menu2 core (review 2026-10-01, C5.3, C5.6,
-- C5.7):
--   1. W.Slider frames are unnamed: a name per slider left one permanent
--      global (MSUF2NativeSlider<serial>) behind for every slider ever built.
--   2. Menu text is translated once. Theme font strings and buttons translate
--      on SetText, so a caller that translated first logged the translated
--      text as a missing locale key (M.GetLocaleCoverage, /msuf locale).
--      Every page is built under deDE and every core widget is fed one raw
--      key; a second lookup caused by the menu core fails. Page, preview and
--      search files are reported by their own packages.
--   3. Status and history feedback fade out on MenuTimer tasks. A quiesced
--      menu (hide, combat) cancels those tasks, so the chrome settles at once
--      instead of staying on screen for the next open; feedback refused in
--      combat lockdown never lingers either.
--   4. Diagnostics prints are translated, and a missing version never shows
--      the stale "v5.0 Beta 1" fallback.
--   5. Menu scale input, rounding, drag release, hide and warm-owner reuse.
--      Optional parentWindowPath replaces only the Window module for replay.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_core_text_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, {
    locale = "deDE", open = false,
    beforeCore = arg[3] and function(world)
        local originalLoad, parentPath = world.LoadFile, arg[3]
        function world:LoadFile(path, addonName, namespace)
            if path:match("/MSUF_Menu2_Window%.lua$") then path = parentPath end
            return originalLoad(self, path, addonName, namespace)
        end
    end or nil,
})
local M, core, env, world = mw.M, mw.core, mw.env, mw.world
Check(core.FinalizeLocale() == "deDE", "the deDE pack was not selected")
local L = env.MSUF_L
local translatedOutputs = {}
for key, value in pairs(L) do
    if type(value) == "string" and value ~= key then translatedOutputs[value] = true end
end

-- A lookup of a string that is only a translation (never a key itself) is a
-- second translation of text the menu translated already. The culprit is the
-- first caller above the translating theme setters (T.Font, FontSetText,
-- ButtonSetText, M.Tr): when that line itself translates (Tr(, M.Tr(, Fmt(,
-- M.Format( or tr() and sits in the menu core, the core translated twice.
local sourceLines = {}
local function SourceLine(path, line)
    local lines = sourceLines[path]
    if not lines then
        lines = {}
        local handle = io.open(path, "rb")
        if handle then
            local text = handle:read("*a"):gsub("\r\n", "\n")
            handle:close()
            for each in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = each end
        end
        sourceLines[path] = lines
    end
    return lines[line] or ""
end
local function TranslatesInline(text)
    return text:find("%f[%w_.]Tr%(") or text:find("M%.Tr%(") or text:find("Fmt%(") or text:find("M%.Format%(")
        or text:find("%f[%w_.]tr%(")
end
local function IsMenuCore(source)
    return source:find("MidnightSimpleUnitFrames_Options/Shell/Menu2/", 1, true)
        and not source:find("/Shell/Menu2/Pages/", 1, true) and not source:find("/Shell/Menu2/Preview/", 1, true)
        and not source:find("/Shell/Menu2/Search/", 1, true)
end
local function Culprit()
    for level = 3, 40 do
        local info = debug.getinfo(level, "Sl")
        if not info then return nil end
        local source = info.source:gsub("\\", "/")
        if not source:find("Shell/Menu2/MSUF_Menu2_Theme.lua", 1, true) then
            if not IsMenuCore(source) then return nil end
            local path = source:sub(1, 1) == "@" and source:sub(2) or source
            if not TranslatesInline(SourceLine(path, info.currentline)) then return nil end
            return (source:match("Shell/Menu2/(.+)$") or source) .. ":" .. tostring(info.currentline)
        end
    end
end
local coreDoubles, smokeDoubles = {}, {}
local Translate = core.Translate
core.Translate = function(text, ...)
    if type(text) == "string" and translatedOutputs[text] and rawget(L, text) == nil then
        if text:find("^SMOKE%-DE ") then smokeDoubles[text] = (smokeDoubles[text] or 0) + 1 end
        local site = Culprit()
        if site then coreDoubles[site] = (coreDoubles[site] or 0) + 1 end
    end
    return Translate(text, ...)
end

Check(M.Open("home") ~= false, "the menu did not open")
mw:RunTimers()
local win = Check(M.frame, "the menu window was not built")
MenuWorld.FireVisibilityScripts(win)
local pageKeys = {}
for key in pairs(M.pages) do pageKeys[#pageKeys + 1] = key end
table.sort(pageKeys)
for _, key in ipairs(pageKeys) do
    M.SelectPage(key)
    mw:RunTimers()
end

---------------------------------------------------------------------------
-- 1. Sliders are unnamed
---------------------------------------------------------------------------
local sliders = 0
for _, frame in ipairs(world.widgets.frames) do
    if frame.objectType == "Slider" and frame._msuf2ControlKind == "slider" then
        sliders = sliders + 1
        Check(frame:GetName() == nil, "a menu slider was created with the global name " .. tostring(frame:GetName()))
    end
end
Check(sliders >= 20, "only " .. sliders .. " menu sliders were built; the page sweep did not run")

---------------------------------------------------------------------------
-- 2. One translation per text in the menu core
---------------------------------------------------------------------------
local doubles = {}
for site, count in pairs(coreDoubles) do doubles[#doubles + 1] = count .. "x " .. site end
table.sort(doubles)
Check(#doubles == 0, "the menu core translated already translated text:\n  " .. table.concat(doubles, "\n  "))
-- The core widgets themselves, fed one raw key each: each label is looked up
-- exactly once, whatever setter shows it.
local W, T = M.Widgets, M.Theme
local function Key(name)
    local key = "Smoke " .. name
    rawset(L, key, "SMOKE-DE " .. name)
    translatedOutputs["SMOKE-DE " .. name] = true
    return key
end
local host = env.CreateFrame("Frame", nil, env.UIParent)
host._msuf2Width = 600
local button = T.Button(host, Key("button"), 120, 24)
button:SetText(Key("button text"))
local dropdown = W.Dropdown(host, Key("dropdown"), { { value = 1, text = Key("choice") } }, 200)
dropdown:SetValue(1)
W.Slider(host, Key("slider"), 0, 10, 1)
W.Text(host, Key("text"), 0, 0, 200)
W.LabelAt(host, Key("label"), 0, 0, 200)
W.ControlCard(host, Key("card"), nil, 0, 0, 200, 80)
W.ToggleAt(host, Key("toggle"), 0, 0)
W.SwitchAt(host, Key("switch"), 0, 0)
W.TextInput(host, Key("input"), 200)
W.Segment(host, Key("segment"), { { value = 1, text = Key("segment choice") } }, 200)
W.Button(host, Key("plain button"), 120)
M.ShowStatusFeedback(Key("status"), "info", 1)
local leaked = {}
for text, count in pairs(smokeDoubles) do leaked[#leaked + 1] = count .. "x " .. text end
table.sort(leaked)
Check(#leaked == 0, "a core widget translated its label twice:\n  " .. table.concat(leaked, "\n  "))
Check(button._msuf2Label:GetText() == "SMOKE-DE button text" and dropdown._msuf2Label:GetText() == "SMOKE-DE choice",
    "the core widgets no longer show their translated labels")
core.Translate = Translate

---------------------------------------------------------------------------
-- 3. Transient chrome settles when the menu quiesces
---------------------------------------------------------------------------
local runtime = Check(M.MenuRuntime, "the menu runtime is missing")
local status = Check(win.status and win.status.feedbackText, "the status feedback line is missing")
local history = Check(M.historyControls and M.historyControls.feedback, "the history feedback line is missing")
M.HideSlashMenuAndMinibar(win)
mw:RunTimers()
Check(M.Open("home") ~= false and win:IsShown(), "the menu did not reopen")
mw:RunTimers()
M.ShowStatusFeedback("Reset failed: defaults unavailable", "danger", 5)
M.ShowHistoryFeedback("Smoke change", 5)
Check(status:GetText() == L["Reset failed: defaults unavailable"], "status feedback was not shown translated: " .. tostring(status:GetText()))
Check((history:GetText() or "") ~= "", "history feedback was not shown")
M.HideSlashMenuAndMinibar(win)
mw:RunTimers()
Check(runtime:PendingTaskCount() == 0, "the hidden menu kept delayed work")
Check((status:GetText() or "") == "" and status:GetAlpha() == 0, "status feedback stayed on screen after the menu quiesced")
Check((history:GetText() or "") == "", "history feedback stayed on screen after the menu quiesced")
Check(M.Open("home") ~= false, "the menu did not reopen")
mw:RunTimers()
-- Refused in lockdown: the fade task is never queued, so nothing may stay.
world.widgets:SetCombat(true)
M.ShowStatusFeedback("Combat locked", "combat", 5)
M.ShowHistoryFeedback("Smoke change", 5)
world.widgets:SetCombat(false)
Check((status:GetText() or "") == "", "status feedback refused in lockdown stayed set")
Check((history:GetText() or "") == "", "history feedback refused in lockdown stayed set")

---------------------------------------------------------------------------
-- 4. Translated diagnostics, no stale version fallback
---------------------------------------------------------------------------
local Commands = Check(core.SlashCommands, "the slash command registry is missing")
local function LastPrint() return world.prints[#world.prints] or "" end
Commands.Get("locale").run("")
Check(LastPrint():find(L["Locale %s: %d keys seen, %d missing translations."]:sub(1, 7), 1, true),
    "/msuf locale printed untranslated text: " .. LastPrint())
Commands.Get("firstload").run("bogus")
Check(LastPrint():find((L["Usage: %s"]:gsub("%%s", "")), 1, true), "/msuf firstload usage printed untranslated text: " .. LastPrint())
local getVersion = core.GetAddonVersion
core.GetAddonVersion = function() return nil end
win.status._msuf2VersionText = nil
win:RefreshStatus()
core.GetAddonVersion = getVersion
Check(not tostring(win.status.versionText:GetText() or ""):find("5.0", 1, true),
    "a missing version showed the stale fallback " .. tostring(win.status.versionText:GetText()))

---------------------------------------------------------------------------
-- 5. Menu scale construction and its unchanged input/owner lifecycle
---------------------------------------------------------------------------
local scaleControl = Check(win.menuScaleControl, "menu scale control missing")
local scaleSlider = Check(win.menuScaleSlider, "menu scale slider missing")
Check(scaleControl.slider == scaleSlider and scaleSlider:GetParent() == scaleControl,
    "menu scale control ownership changed")
Check(scaleControl:GetWidth() == 190 and scaleControl:GetHeight() == 22,
    "menu scale chrome geometry changed")
local minimum, maximum = scaleSlider:GetMinMaxValues()
Check(minimum == 25 and maximum == 200 and scaleSlider.valueStep == 5,
    "menu scale range or step changed")
local meta = Check(scaleSlider._msuf2SearchMeta, "menu scale metadata missing")
Check(meta.settingKey == "general.slashMenuScale" and meta.historyMode == "none",
    "menu scale setting or history policy changed")
local scaleCommand = Check(meta.command, "menu scale command missing")
local general = M.GetGeneralDB()
local savedScale = general.slashMenuScale
local function ScaleEquals(value)
    return math.abs((general.slashMenuScale or 0) - value) < 0.000001
end
local function ScaleScript(name, ...)
    local handler = Check(scaleSlider:GetScript(name), "menu scale script missing: " .. name)
    return handler(scaleSlider, ...)
end
general.slashMenuScale = 0.8
win.RefreshMenuScaleControl()
Check(scaleSlider:GetValue() == 100 and ScaleEquals(0.8), "menu scale refresh wrote or changed the legacy reference")
Check(scaleControl.label:GetText() == M.Format("Menu %d%%", 100), "menu scale label lost translation")
scaleCommand.set(107)
Check(scaleSlider:GetValue() == 105 and ScaleEquals(0.84), "menu scale command did not round and apply")
Check(math.abs(win:GetScale() - 0.84 * 1.08) < 0.000001, "menu scale did not reach the owning window")
scaleCommand.set(0)
Check(scaleSlider:GetValue() == 25 and ScaleEquals(0.2), "menu scale lower clamp changed")
scaleCommand.set(999)
Check(scaleSlider:GetValue() == 200 and ScaleEquals(1.6), "menu scale upper clamp changed")
scaleCommand.set("invalid")
Check(scaleSlider:GetValue() == 100 and ScaleEquals(0.8), "menu scale invalid-input fallback changed")
ScaleScript("OnMouseWheel", -1)
Check(scaleSlider:GetValue() == 95 and ScaleEquals(0.76), "menu scale wheel did not commit one step")
ScaleScript("OnMouseWheel", 0)
Check(scaleSlider:GetValue() == 95 and ScaleEquals(0.76), "zero wheel changed menu scale")
local savedCursor, savedButton = env.GetCursorPosition, env.IsMouseButtonDown
local savedLeft, savedWidth, savedEffective = scaleSlider.GetLeft, scaleSlider.GetWidth, scaleSlider.GetEffectiveScale
local cursor, held = 120, true
env.GetCursorPosition = function() return cursor, 0 end
env.IsMouseButtonDown = function(button) return button == "LeftButton" and held end
scaleSlider.GetLeft = function() return 10 end
scaleSlider.GetWidth = function() return 100 end
scaleSlider.GetEffectiveScale = function() return 2 end
ScaleScript("OnMouseDown", "RightButton")
Check(not scaleSlider._msuf2MenuScaleDragging and ScaleEquals(0.76), "right click started menu scale drag")
ScaleScript("OnMouseDown", "LeftButton")
Check(scaleSlider:GetValue() == 115 and scaleSlider._msuf2MenuScaleDragging and ScaleEquals(0.76),
    "menu scale press lost cursor transform or committed before release")
held = false
ScaleScript("OnUpdate", 0.016)
Check(not scaleSlider._msuf2MenuScaleDragging and not scaleSlider:GetScript("OnUpdate") and ScaleEquals(0.92),
    "menu scale drag release lost commit or retained idle work")
held, cursor = true, 220
ScaleScript("OnMouseDown", "LeftButton")
ScaleScript("OnMouseUp", "LeftButton")
Check(ScaleEquals(1.6) and not scaleSlider:GetScript("OnUpdate"), "menu scale mouse-up commit changed")
cursor = 20
ScaleScript("OnMouseDown", "LeftButton")
ScaleScript("OnHide")
Check(not scaleSlider._msuf2MenuScaleDragging and not scaleSlider:GetScript("OnUpdate") and ScaleEquals(1.6),
    "hiding the scale control committed a partial drag or retained work")
env.GetCursorPosition, env.IsMouseButtonDown = savedCursor, savedButton
scaleSlider.GetLeft, scaleSlider.GetWidth, scaleSlider.GetEffectiveScale = savedLeft, savedWidth, savedEffective
for _ = 1, 3 do
    M.HideSlashMenuAndMinibar(win)
    mw:RunTimers()
    Check(M.Open("home") ~= false, "menu scale reopen failed")
    mw:RunTimers()
    Check(win.menuScaleControl == scaleControl and win.menuScaleSlider == scaleSlider,
        "menu scale warm reopen replaced its owners")
end
general.slashMenuScale = savedScale
win.RefreshMenuScaleControl()

print(string.format("menu_core_text_smoke: ok (%s: %d unnamed sliders, no core double translation over %d pages, chrome settles on quiesce, translated diagnostics)",
    flavor, sliders, #pageKeys))
