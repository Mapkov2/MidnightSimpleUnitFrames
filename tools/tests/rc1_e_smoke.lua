-- rc1_e_smoke.lua <repoRoot>
--
-- rc1 package E: text, encoding and locale regressions.
--
--   DM-2  The Guided Tour stage hints carried a double-encoded middle dot
--         (C3 82 C2 B7: a capital A circumflex before the dot), so the exact-key
--         lookup missed and every client showed the English hint although all
--         twelve packs translate the correct key. No shipped Lua file may hold
--         UTF-8 text that was re-encoded as Latin-1 and saved again.
--   DM-3  Aura filter switch labels (Non-Player Auras, Only mine, Hide
--         permanent, Crowd control) were missing from every pack.
--   R6-CX-CX-04  ruRU named the ready check "ready cheque" and the raid
--         assistant icon "help"; the client calls them Проверка готовности
--         and Помощник. Fury stays Гнев: that is the client's name of the
--         Demon Hunter resource the key labels.
--   R6-C8-C8-07 / R-C7-08  Priority Frames badges and the pin count, and the
--         Layer overview section titles and More/Less row, glued a number to
--         separately translated fragments ("0 " .. Tr("visible")); they use
--         whole-phrase format keys now. Checked on the real Priority Frames
--         page and Layer overview popup in Russian, whose phrases reorder.
--   Crowd Control  The Group filter choice ("Crowd Control") and the Unit
--         switch ("Crowd control") name one thing; every pack uses one word
--         for both (frFR, itIT, ptBR and ruRU carried literal "crowd" terms).
--   Ready Check  Every pack names the ready check as its client does (DBM's
--         native localizations, the established term): Bereitschaftscheck,
--         Comprobación de banda, Appel, Controllo gruppo, 전투 준비,
--         Verificação de prontidão, 就位确认, 準備確認.
--   Filter blocks  Every label and tooltip the Unit and Group aura filter
--         sections show ("Important", "Raid combat", their tooltips, the Group
--         filter choices) exists in all twelve packs; built for real on
--         Mainline (full Blizzard token filters) and Vanilla (reduced set).
--   RP-3  The exported MSUF_GetFontPreviewObject raised on a font key no
--         provider has registered (yet); it previews the default face like the
--         rest of the font pipeline now.
--
-- Loads the real locale loader and packs, and boots each client's real core
-- and Options graph (tools/tests/client_world.lua). Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil, "rc1_e_smoke boots the real TOC graph; run it with plain Lua 5.1")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local LOCALES = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local ENGLISH = { enUS = true, enGB = true }

-- Each pack executed as the client runs it: the shared loader, then the pack.
local packs = {}
for _, locale in ipairs(LOCALES) do
    local env = { GetLocale = function() return locale end }
    env._G = env
    setmetatable(env, { __index = _G })
    local namespace = {}
    env.MSUF_NS, env.MSUF = namespace, namespace
    for _, file in ipairs({ "MSUF_Localization", locale }) do
        local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Locales/" .. file .. ".lua"))
        setfenv(chunk, env)
        chunk("MidnightSimpleUnitFrames", namespace)
    end
    assert(namespace.FinalizeLocale() == locale, "the " .. locale .. " pack did not select itself")
    packs[locale] = namespace.L
end

-- Every pack defines key; the ten translated packs translate it.
local function CheckTranslated(key, what)
    for _, locale in ipairs(LOCALES) do
        local value = rawget(packs[locale], key)
        if Check(type(value) == "string", locale .. ": " .. what .. " has no locale key: " .. key) then
            Check(ENGLISH[locale] or value ~= key, locale .. ": " .. what .. " stays English: " .. key)
        end
    end
end

---------------------------------------------------------------------------
-- 1. DM-2: no UTF-8 re-encoded as Latin-1 in shipped Lua.
---------------------------------------------------------------------------
-- A two-byte character saved through a Latin-1 round trip starts with C3 82
-- or C3 83 followed by C2: U+00B7 becomes C3 82 C2 B7 and U+00FC becomes
-- C3 83 C2 BC.
local REENCODED = { "\195\130\194", "\195\131\194" }
-- Known occurrences that are not this package's to change, each with its reason.
local KNOWN = {
    -- The owner reverted the UTF-8 fix of this search alias (d235a75c,
    -- 2026-10-05); the alias stays as it is until that decision changes.
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua"] = "schl\195\131\194\188sselstein",
}
local scanned = 0
local listing = assert(io.popen('git -C "' .. root .. '" ls-files -- MidnightSimpleUnitFrames MidnightSimpleUnitFrames_Options', "r"))
for path in listing:lines() do
    if path:match("%.lua$") then
        scanned = scanned + 1
        local source = Read(path)
        local known = KNOWN[path]
        if known then
            local at = source:find(known, 1, true)
            Check(at ~= nil, path .. ": the known re-encoded text is gone; remove its KNOWN row")
            if at then source = source:sub(1, at - 1) .. source:sub(at + #known) end
        end
        for _, marker in ipairs(REENCODED) do
            local at = source:find(marker, 1, true)
            Check(at == nil, path .. ": UTF-8 re-encoded as Latin-1 near '"
                .. (at and source:sub(math.max(1, at - 24), at + 8):gsub("[\r\n]", " ") or "") .. "'")
        end
    end
end
listing:close()
Check(scanned > 400, "the encoding scan saw only " .. scanned .. " shipped Lua files")

---------------------------------------------------------------------------
-- 2. DM-2: the Guided Tour hints translate in every pack.
---------------------------------------------------------------------------
local TOUR = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_GuidedTour.lua"
local tourCues = {}
for cue in Read(TOUR):gmatch('Tr%("([^"]*\194\183[^"]*)"%)') do tourCues[#tourCues + 1] = cue end
Check(#tourCues >= 8, "the Guided Tour lost its stage hints with a middle dot: " .. #tourCues)
for _, cue in ipairs(tourCues) do CheckTranslated(cue, "Guided Tour hint") end

---------------------------------------------------------------------------
-- 3. DM-3: the aura filter switch labels exist in all twelve packs.
---------------------------------------------------------------------------
-- The exact literals the pages pass to BindSwitch, the filter specs and VT.
local AURA_PAGES = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local AURA_LABELS = {
    { "Non-Player Auras", "MSUF_Menu2_Auras.lua", 'BindSwitch(ctx, section, "Non-Player Auras",' },
    { "Non-Player Auras", "MSUF_Menu2_Auras_Group.lua", 'BindSwitch(ctx, section, "Non-Player Auras",' },
    { "Only mine", "MSUF_Menu2_Auras.lua", 'BindSwitch(ctx, section, "Only mine",' },
    { "Only mine", "MSUF_Menu2_Auras_Group.lua", 'VT("ALL", "All", "Player", "Only mine", "NonPlayer", "Non-Player Auras")' },
    { "Hide permanent", "MSUF_Menu2_Auras.lua", 'BindSwitch(ctx, section, "Hide permanent",' },
    { "Hide permanent", "MSUF_Menu2_Auras_Group.lua", 'BindSwitch(ctx, section, "Hide permanent",' },
    { "Non-player auras", "MSUF_Menu2_Auras.lua", '{ "Non-player auras", "nonPlayer",' },
    { "Crowd control", "MSUF_Menu2_Auras.lua", '{ "Crowd control", "crowdControl",' },
}
local auraKeys, seenAuraKey = {}, {}
for _, row in ipairs(AURA_LABELS) do
    local key, file, call = row[1], row[2], row[3]
    Check(Read(AURA_PAGES .. file):find(call, 1, true) ~= nil, file .. " no longer labels a control with " .. call)
    if not seenAuraKey[key] then
        seenAuraKey[key] = true
        auraKeys[#auraKeys + 1] = key
        CheckTranslated(key, "aura filter label")
    end
end

---------------------------------------------------------------------------
-- 4. R6-CX-CX-04: ruRU uses the client's own terms for these labels.
---------------------------------------------------------------------------
local RU_TERMS = {
    ["Ready Check"] = "Проверка готовности",
    ["Assist"] = "Помощник",
    ["Fury"] = "Гнев",
}
for key, expected in pairs(RU_TERMS) do
    local value = rawget(packs.ruRU, key)
    Check(value == expected, "ruRU: " .. key .. " reads " .. tostring(value) .. ", not the client term " .. expected)
end

for _, locale in ipairs(LOCALES) do
    local group, unit = rawget(packs[locale], "Crowd Control"), rawget(packs[locale], "Crowd control")
    Check(ENGLISH[locale] or (group ~= nil and group == unit),
        locale .. ": Crowd Control reads " .. tostring(group) .. " but Crowd control reads " .. tostring(unit))
end

local READY_CHECK = {
    deDE = "Bereitschaftscheck", esES = "Comprobación de banda", esMX = "Comprobación de banda",
    frFR = "Appel", itIT = "Controllo gruppo", koKR = "전투 준비", ptBR = "Verificação de prontidão",
    ruRU = "Проверка готовности", zhCN = "就位确认", zhTW = "準備確認",
}
for locale, expected in pairs(READY_CHECK) do
    local value = rawget(packs[locale], "Ready Check")
    Check(value == expected, locale .. ": Ready Check reads " .. tostring(value) .. ", not the client term " .. expected)
end

---------------------------------------------------------------------------
-- 5. R6-C8-C8-07 / R-C7-08: counts are whole-phrase format keys.
---------------------------------------------------------------------------
local FORMAT_KEYS = {
    "%s visible", "%s pinned", "%s slots", "%s saved", "%d saved players",
    "Search results - MSUF Layers 0-30 (%d) | %s", "%s - MSUF Layers 0-30 (%d) | %s",
    "All other MSUF Layers 0-30 (%d) | %s", "More (%d)", "Less (%d)",
}
for _, key in ipairs(FORMAT_KEYS) do CheckTranslated(key, "count phrase") end

-- An anchored Lua pattern for a format: %s captures text, %d captures digits.
local function FormatPattern(format)
    local parts, from = {}, 1
    local function Literal(piece) return (piece:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    for at, spec, after in format:gmatch("()%%([sd])()") do
        parts[#parts + 1] = Literal(format:sub(from, at - 1))
        parts[#parts + 1] = spec == "d" and "(%d+)" or "(.-)"
        from = after
    end
    parts[#parts + 1] = Literal(format:sub(from))
    return "^" .. table.concat(parts) .. "$"
end

do
    local ru = packs.ruRU
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local painted = {}
    local mw = MenuWorld.Open(root, "Mainline", { locale = "ruRU", page = "home",
        beforeCore = function(world)
            local SetText = world.widgets.Methods.SetText
            world.widgets.Methods.SetText = function(self, value, ...)
                if type(value) == "string" then painted[value] = true end
                return SetText(self, value, ...)
            end
        end,
        beforeOptions = function(world) assert(world.core.FinalizeLocale() == "ruRU") end })
    local M = mw.M

    -- Priority Frames: nothing pinned or shown, five slots.
    M.EagerSections = true
    Check(mw:Select("gf_priority"), "the Priority Frames page did not open")
    mw:RunTimers()
    for _, case in ipairs({
        { "%s visible", "0", "visible" }, { "%s pinned", "0", "pinned" }, { "%s slots", "5", "slots" },
        { "%s saved", "0", "saved" }, { "%d saved players", 0, "saved players" },
    }) do
        local format, value, fragment = case[1], case[2], case[3]
        local expected = type(ru[format]) == "string" and string.format(ru[format], value) or "(no " .. format .. ")"
        Check(painted[expected], "Priority Frames does not show the whole phrase " .. expected)
        Check(not painted[tostring(value) .. " " .. tostring(ru[fragment])],
            "Priority Frames glued " .. tostring(value) .. " to the fragment " .. tostring(ru[fragment]))
    end

    -- Layer overview: context section, More, All other, Less, search results.
    local hint = ru["EDIT: click green number"]
    local popup = M.ShowLayerOverview(nil)
    mw:RunTimers()
    local function VisibleRows()
        local list = {}
        for _, row in ipairs(popup._rows or {}) do
            if row:IsShown() then list[#list + 1] = row end
        end
        return list
    end
    -- The section or More row whose text matches format; its captures.
    local function FindRow(rowType, format)
        local pattern = FormatPattern(tostring(ru[format]))
        local rows = VisibleRows()
        for index, row in ipairs(rows) do
            local label = row._rowType == rowType and row._label and row._label:GetText()
            if label and label:find(pattern) then
                local dataRows = 0
                while rows[index + dataRows + 1] and rows[index + dataRows + 1]._rowType == "data" do
                    dataRows = dataRows + 1
                end
                return row, dataRows, label:match(pattern)
            end
        end
        local shown = {}
        for _, row in ipairs(rows) do
            if row._rowType ~= "data" then shown[#shown + 1] = tostring(row._label and row._label:GetText()) end
        end
        Check(false, "the Layer overview shows no " .. rowType .. " row for " .. format .. "; it shows: "
            .. table.concat(shown, " / "))
    end
    local row, dataRows, label, count, edit = FindRow("section", "%s - MSUF Layers 0-30 (%d) | %s")
    if row then
        Check(label ~= "" and tonumber(count) == dataRows and edit == hint,
            "the Layer overview context title reads " .. tostring(row._label:GetText()))
    end
    local more, _, moreCount = FindRow("more", "More (%d)")
    if more then
        more:GetScript("OnMouseDown")(more, "LeftButton")
        local less, _, lessCount = FindRow("more", "Less (%d)")
        Check(less == nil or lessCount == moreCount, "the Less row counts " .. tostring(lessCount))
        local other, otherRows, otherCount, otherEdit = FindRow("section", "All other MSUF Layers 0-30 (%d) | %s")
        Check(other == nil or (tonumber(otherCount) == otherRows and otherCount == moreCount and otherEdit == hint),
            "the Layer overview title of the other layers reads " .. tostring(other and other._label:GetText()))
    end
    popup._search:SetText("health")
    Check(M.RefreshLayerOverviewContext(), "the Layer overview did not rebuild for a search")
    local found, foundRows, foundCount, foundEdit = FindRow("section", "Search results - MSUF Layers 0-30 (%d) | %s")
    Check(found == nil or (tonumber(foundCount) == foundRows and foundRows > 0 and foundEdit == hint),
        "the Layer overview search title reads " .. tostring(found and found._label:GetText()))
    M.HideLayerOverview()
end

---------------------------------------------------------------------------
-- 7. The aura filter sections show no untranslated label or tooltip.
---------------------------------------------------------------------------
-- Cognates a pack spells exactly like the English key. enUS and enGB fall back to
-- the key itself, so the ten translated packs are the ones checked here.
local SAME_WORD = { esES = { Cancelable = true }, esMX = { Cancelable = true }, frFR = { Raid = true } }
local function LineOf(relative, needle)
    local source = Read(relative):gsub("\r\n", "\n")
    local at = Check(source:find(needle, 1, true), relative .. " no longer defines " .. needle)
    if not at then return -1 end
    local _, lines = source:sub(1, at):gsub("\n", "")
    return lines + 1
end
local FILTER_BUILDERS = {
    ["MSUF_Menu2_Auras.lua"] = LineOf(AURA_PAGES .. "MSUF_Menu2_Auras.lua",
        "\nlocal function BuildCompactUnitAuraFilters(ctx, b, unit, lane)"),
    ["MSUF_Menu2_Auras_Group.lua"] = LineOf(AURA_PAGES .. "MSUF_Menu2_Auras_Group.lua",
        "\nlocal function BuildCompactGroupAuraFilters(ctx, b, scope, lane)"),
}
local filterTexts = 0
for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local mw = MenuWorld.Open(root, flavor, { locale = "ruRU", page = "home",
        beforeOptions = function(world) assert(world.core.FinalizeLocale() == "ruRU") end })
    local M, core = mw.M, mw.core
    local shown, order = {}, {}
    -- True while a call runs inside one of the two filter section builders.
    local function InFilterBuilder()
        for level = 3, 80 do
            local info = debug.getinfo(level, "S")
            if not info then return false end
            local file = info.source:gsub("\\", "/"):match("Shell/Menu2/Pages/([%w_]+%.lua)$")
            if file and FILTER_BUILDERS[file] == info.linedefined then return true end
        end
        return false
    end
    local function Record(value)
        if type(value) == "string" and value:find("%a") and not value:find("|c", 1, true)
            and not shown[value] and InFilterBuilder() then
            shown[value] = true
            order[#order + 1] = value
        end
    end
    local Translate = core.Translate
    core.Translate = function(value, ...) Record(value); return Translate(value, ...) end
    local AddTooltip = M.AddTooltip
    M.AddTooltip = function(control, title, body, ...)
        Record(title); Record(body)
        return AddTooltip(control, title, body, ...)
    end
    M.EagerSections = true
    local function Every(value) return setmetatable({}, { __index = function() return value end }) end
    for _, lane in ipairs({ "buff", "debuff" }) do
        local function Tool(t, key)
            local state = { [lane] = "filters" }
            rawset(t, key, state)
            return state
        end
        M.unitAuraTabSelection = Every(lane)
        M.unitAuraToolSelection = setmetatable({}, { __index = Tool })
        M.InvalidatePage("uf_target")
        Check(mw:Select("uf_target"), flavor .. ": the Target page did not open on the " .. lane .. " filters")
        M.gfAuraLaneSelection = Every(lane)
        M.gfAuraToolSelection = setmetatable({}, { __index = Tool })
        M.InvalidatePage("gf_auras")
        Check(mw:Select("gf_auras"), flavor .. ": the Group Auras page did not open on the " .. lane .. " filters")
    end
    core.Translate, M.AddTooltip = Translate, AddTooltip
    Check(#order >= (flavor == "Mainline" and 60 or 8), flavor .. ": the filter sections showed only " .. #order .. " texts")
    filterTexts = filterTexts + #order
    for _, value in ipairs(order) do
        for _, locale in ipairs(LOCALES) do
            local translated = rawget(packs[locale], value)
            if not ENGLISH[locale] and Check(type(translated) == "string", flavor .. " " .. locale
                .. ": the aura filter section shows " .. value .. " without a locale key") then
                Check(translated ~= value or (SAME_WORD[locale] or {})[value],
                    flavor .. " " .. locale .. ": the aura filter section shows " .. value .. " in English")
            end
        end
    end
end

---------------------------------------------------------------------------
-- The real Options graph shows the packs' text (exact-key lookup).
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function OptionsTr(flavor, locale)
    local world = World.New(root, flavor, { locale = locale })
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. " " .. locale .. ": boot failed in " .. tostring(failure and failure.file)
        .. ": " .. tostring(failure and failure.message))
    assert(world.core.FinalizeLocale() == locale, flavor .. ": the world did not select " .. locale)
    return world.options.MSUF2.Tr, world
end

for _, case in ipairs({ { "Mainline", "deDE" }, { "Forever", "ruRU" }, { "Mists", "zhCN" } }) do
    local flavor, locale = case[1], case[2]
    local Tr, world = OptionsTr(flavor, locale)
    for _, cue in ipairs(tourCues) do
        local shown = Tr(cue)
        Check(shown == rawget(packs[locale], cue) and shown ~= cue,
            flavor .. " " .. locale .. ": the Guided Tour hint shows " .. tostring(shown))
    end
    for _, key in ipairs(auraKeys) do
        local shown = Tr(key)
        Check(shown == rawget(packs[locale], key) and shown ~= key,
            flavor .. " " .. locale .. ": the aura filter label " .. key .. " shows " .. tostring(shown))
    end
    Check(Tr("Ready Check") == READY_CHECK[locale], flavor .. " " .. locale .. ": Ready Check shows " .. tostring(Tr("Ready Check")))
    if locale == "ruRU" then
        for key, expected in pairs(RU_TERMS) do
            Check(Tr(key) == expected, flavor .. " ruRU: " .. key .. " shows " .. tostring(Tr(key)))
        end
    end
    -- 6. RP-3: an unknown font key previews the pipeline's default face.
    local env = world.env
    local unknown = "MSUF_rc1_UnregisteredFont"
    local ok, preview = pcall(env.MSUF_GetFontPreviewObject, unknown)
    if Check(ok, flavor .. ": MSUF_GetFontPreviewObject raised on an unknown key: " .. tostring(preview)) then
        local face = preview and preview.GetFont and preview:GetFont()
        local default = env.MSUF_ResolveFontPath(nil, 14, "", unknown)
        Check(type(default) == "string" and default ~= "" and face == default,
            flavor .. ": the unknown key previews " .. tostring(face) .. ", not the default face " .. tostring(default))
        Check(env.MSUF_GetFontPreviewObject(unknown) == preview, flavor .. ": the preview object is not reused")
    end
    local known = env.MSUF_ResolveFontKeyPath("EXPRESSWAY")
    local expressway = env.MSUF_GetFontPreviewObject("EXPRESSWAY")
    Check(type(known) == "string" and expressway:GetFont() == known,
        flavor .. ": a registered key previews " .. tostring(expressway:GetFont()) .. ", not " .. tostring(known))
end

if #failures > 0 then
    error("rc1_e_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("rc1_e_smoke: ok (" .. scanned .. " shipped Lua files single-encoded, "
    .. #tourCues .. " Guided Tour hints and " .. #auraKeys .. " aura filter labels translated in 12 packs"
    .. " and on Mainline, Forever and Mists, ruRU client terms, whole-phrase counts on Priority Frames"
    .. " and the Layer overview, unknown font keys preview the default face, "
    .. filterTexts .. " aura filter texts translated on Mainline and Vanilla)")
