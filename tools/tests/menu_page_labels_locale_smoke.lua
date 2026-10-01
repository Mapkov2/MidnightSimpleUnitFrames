-- menu_page_labels_locale_smoke.lua <repoRoot> <flavor>
--
-- Every menu-facing string must exist in all twelve language packs.
-- locale_key_coverage_smoke compares the packs with each other, so a label that
-- no pack defines passes it. This smoke closes that gap for the page files it
-- names: it boots the flavor's real core and Options graph
-- (tools/tests/client_world.lua), builds the pages that use those files, and
-- records every string the menu translates while doing so (MSUF.Translate),
-- every tooltip, every dropdown entry and every color shortcut target, each
-- attributed to the page file whose call produced it. A string that appears
-- literally in that page file and is missing from any of the ten translated
-- packs fails, as does a missing entry from REQUIRED (strings of other page
-- files whose controls these changes touched).
--
-- enUS and enGB fall back to the key itself (MSUF_Localization.lua), so the ten
-- other packs are the ones checked.
--
-- Plain Lua 5.1 with the repo root and a flavor (a client matrix Suffix or
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_page_labels_locale_smoke boots the real TOC graph; run it with plain Lua 5.1")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

-- Page files whose literal labels must all be translated, and the pages that build them.
local CHECKED_FILES = {
    "MSUF_Menu2_SwingTimers.lua", "MSUF_Menu2_UnitFrameVisuals.lua", "MSUF_Menu2_ResourceExtras.lua",
    "MSUF_Menu2_ProfileVariants.lua", "MSUF_Menu2_ProfileSync.lua",
}
local PAGES = { "swingtimers", "uf_player", "uf_target", "classpower", "opt_colors", "opt_castbar", "profiles" }
-- Labels of other page files that these pages show and must translate too, and
-- labels these files show only in a state the build does not reach.
-- ("Show on Arena castbars" is still English in every pack: localized search on
-- Classic Era finds the Castbar page for "cast bar" only through that English label,
-- see search_locale_queries_smoke.)
-- The Additional resources toggles and colors are labelled through the shared
-- Advanced page builders, so their translations are recorded for those files.
local REQUIRED = {
    "Show on Target castbar", "Show on Focus castbar", "Show on Boss castbars",
    "Place GCD bar separately", "Spell-specific channel tick markers",
    "Mana spend preview", "Regeneration pause after spending", "Mana return pulse",
    "Arcane Surge window timer", "Arcane window warning (seconds)", "Arcane window bar",
    "Arcane window warning text", "Arcane window text", "Seconds left", "Global cooldowns you can still start",
    "Seconds and global cooldowns", "Show the time from (seconds left, 0 = always)",
    "Warn during the last global cooldown", "Arcane Soul phase bar",
    "The saved profile variants cannot be read (%s). They are kept unchanged, and editing them here is blocked.",
    -- Group and aura page formats that replaced concatenated text
    -- (menu_pages_quality_smoke section 10).
    "%s px", "Name %s", "HP %s", "Power %s", "Offline %d%%", "Offline visible", "Offline hidden",
    "Border %s", "IDs: %s", "%s: %s", "%s Indicator", "Group %s", "Texture: %s",
}

---------------------------------------------------------------------------
-- The ten translated packs, executed as the client runs them.
---------------------------------------------------------------------------
local LOCALES_DIR = "MidnightSimpleUnitFrames/Locales/"
local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local function LoadPack(locale)
    local previousGetLocale, previousCreateFrame = _G.GetLocale, _G.CreateFrame
    local previousNS, previousMSUF, previousL = _G.MSUF_NS, _G.MSUF, _G.MSUF_L
    _G.GetLocale = function() return locale end
    _G.CreateFrame = nil
    local namespace = {}
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    assert(loadfile(root .. "/" .. LOCALES_DIR .. "MSUF_Localization.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(root .. "/" .. LOCALES_DIR .. locale .. ".lua"))("MidnightSimpleUnitFrames", namespace)
    namespace.FinalizeLocale()
    local keys = {}
    for key, value in pairs(namespace.L) do
        if type(key) == "string" and type(value) == "string" then keys[key] = true end
    end
    _G.GetLocale, _G.CreateFrame = previousGetLocale, previousCreateFrame
    _G.MSUF_NS, _G.MSUF, _G.MSUF_L = previousNS, previousMSUF, previousL
    return keys
end
local packs = {}
for _, locale in ipairs(LOCALES) do packs[locale] = LoadPack(locale) end
local function MissingIn(key)
    local missing = {}
    for _, locale in ipairs(LOCALES) do
        if not packs[locale][key] then missing[#missing + 1] = locale end
    end
    return missing
end

---------------------------------------------------------------------------
-- Boot the client and give the page builders the widget surface they use.
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor):Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
for name, method in pairs({
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"),
    SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
    SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
    SetPropagateMouseWheel = Store("propagateMouseWheel"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, ClearFocus = function() end, SetFocus = function() end,
    HighlightText = function() end, SetCursorPosition = function() end, GetCursorPosition = function() return 0 end,
    SetTextInsets = function() end, SetTimerDuration = function() end,
    SetScrollChild = Store("scrollChild"), GetScrollChild = Fetch("scrollChild"), SetVerticalScroll = Store("verticalScroll"),
    GetVerticalScroll = function(self) return self.verticalScroll or 0 end, GetVerticalScrollRange = function() return 0 end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local env, MSUF = world.env, world.core
local M = Check(world.options.MSUF2, "Menu2 did not load")
env.InCombatLockdown = function() return false end
-- The GCD Bar section exists only where the client drives the bar natively.
env.C_Spell = setmetatable({ GetSpellCooldownDuration = function() return nil end },
    { __index = function() return World.Stub end })
env.MSUF_EnsureDB(true)
-- A variant and a sync group, so the Profiles page builds both editors in full.
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB, Other = { general = {} } }, char = {}, global = {} }
MSUF.ProfileRuntime.Apply = function() end
Check(MSUF.ProfileVariants.Replace(env.MSUF_DB, { version = 1, entries = { { name = "Check", patch = {} } } }),
    "harness: the profile variant was not saved")
Check(MSUF.ProfileSync.Replace({ { name = "Shared", members = { Default = true, Other = true }, modules = { unitframes = true } } }),
    "harness: the sync group was not saved")
M.frame = M.frame or { IsShown = function() return true end }
M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)
M.GetContentMetrics = M.GetContentMetrics or function() return 900, 800 end

---------------------------------------------------------------------------
-- Record every translated string, by the page file whose call produced it.
---------------------------------------------------------------------------
local byFile = {}
local function PageFile()
    for level = 3, 60 do
        local info = debug.getinfo(level, "S")
        if not info then return nil end
        local file = info.source:gsub("\\", "/"):match("Shell/Menu2/Pages/([%w_]+%.lua)")
        if file then return file end
    end
end
local function Record(text, file)
    file = file or PageFile()
    if type(text) == "string" and file then
        byFile[file] = byFile[file] or {}
        byFile[file][text] = true
    end
end
local Translate = Check(MSUF.Translate, "MSUF.Translate is missing")
MSUF.Translate = function(text, ...)
    Record(text)
    return Translate(text, ...)
end
local AddTooltip = M.AddTooltip
M.AddTooltip = function(control, title, text, ...)
    local file = PageFile()
    Record(title, file)
    Record(text, file)
    if AddTooltip then return AddTooltip(control, title, text, ...) end
end
-- Dropdown entries and color shortcut targets are translated when the list or
-- the popup opens; open them here.
local W = M.Widgets
local Dropdown = W.Dropdown
W.Dropdown = function(section, label, values, ...)
    local widget = Dropdown(section, label, values, ...)
    local file = PageFile()
    local list = type(values) == "function" and values() or values
    for _, item in ipairs(type(list) == "table" and list or {}) do
        if type(item) == "table" then Record(item.text, file) end
    end
    return widget
end
local Shortcut = W.AttachContextColorShortcut
if Shortcut then
    W.AttachContextColorShortcut = function(section, opts, ...)
        local file = PageFile()
        if type(opts) == "table" then
            Record(opts.title, file)
            for _, target in ipairs(type(opts.getTargets) == "function" and opts.getTargets() or {}) do
                if type(target) == "table" then Record(target.label, file) end
            end
        end
        return Shortcut(section, opts, ...)
    end
end

local built = {}
for _, key in ipairs(PAGES) do
    if M.pages[key] then
        Check(M.BuildPageEntry(key, true), "the " .. key .. " page did not build")
        world.widgets:RunTimers(20000)
        built[#built + 1] = key
    end
end

---------------------------------------------------------------------------
-- Every literal label of the checked files is translated in every pack.
---------------------------------------------------------------------------
local function Literal(source, text)
    local quoted = '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    return source:find(quoted, 1, true) ~= nil
end
local problems, checked = {}, 0
for _, file in ipairs(CHECKED_FILES) do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/" .. file, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local keys = {}
    for text in pairs(byFile[file] or {}) do
        if text:find("%a") and not text:find("|c", 1, true) and not text:find("|T", 1, true) and Literal(source, text) then
            keys[#keys + 1] = text
        end
    end
    table.sort(keys)
    checked = checked + #keys
    for _, text in ipairs(keys) do
        local missing = MissingIn(text)
        if #missing > 0 then
            problems[#problems + 1] = string.format("%s: %q is missing from %s", file, text, table.concat(missing, ","))
        end
    end
end
for _, text in ipairs(REQUIRED) do
    local missing = MissingIn(text)
    if #missing > 0 then
        problems[#problems + 1] = string.format("required: %q is missing from %s", text, table.concat(missing, ","))
    end
end
Check(#problems == 0, #problems .. " untranslated menu label(s):\n  " .. table.concat(problems, "\n  "))
Check(checked > 0, "no literal label of the checked page files was recorded")
if flavor == "Forever" then
    Check(next(byFile["MSUF_Menu2_SwingTimers.lua"] or {}) ~= nil, "the Swing Timers page recorded no label on WoW Forever")
end

print(string.format("menu_page_labels_locale_smoke: ok (%s; %d literal labels of %d page files on %s translated in %d packs)",
    flavor, checked, #CHECKED_FILES, table.concat(built, ","), #LOCALES))
