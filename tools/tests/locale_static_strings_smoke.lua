-- locale_static_strings_smoke.lua <repoRoot>
--
-- The strings a player sees without opening the page that builds them. Three
-- source-level checks, no client boot:
--
--   1. Search: every label and every breadcrumb segment of both baked search
--      indexes (Search/MSUF_Menu2_Search_StaticIndex_Data*.lua) is translated in
--      the ten packs. Results show Translate(label), and each segment of the
--      breadcrumb through Translate too (MSUF_Menu2_Search_StaticIndex.lua).
--   2. Prompts, chat lines and tooltips: every quoted string handed straight to a
--      translation call (Tr, M.Tr, M.TranslateText, MSUF.Translate, M.Format or an
--      L["..."] lookup) in the addon files of any client is translated. These are
--      the strings no page build or state visit reaches until the player acts.
--   3. tools/locale-same-text-allowlist.tsv stays honest: every row names a string
--      that still exists in the sources or the index, and excuses a pack that
--      really leaves it in English.
--
-- A string counts as translated when the pack defines it as something other than
-- the English key, or the allowlist excuses it for that pack. The bundled release
-- notes, the locale packs, the vendored libraries (calls) and generated alias data
-- are not scanned. menu_page_labels_locale_smoke.lua covers the strings a built
-- page, tooltip or dropdown resolves.
--
-- Plain Lua 5.1 with the repo root as argument 1. A second argument names a file that
-- receives every untranslated string (section, text, where, packs; tab separated).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Packs = assert(loadfile(root .. "/tools/tests/locale_packs.lua"))()
local packs = Packs.Load(root)
local allowlist, allowRows = Packs.ReadAllowlist(root, packs)

local reportPath = arg and arg[2]
local failures, report = {}, {}
local function Fail(section, message) failures[#failures + 1] = section .. ": " .. message end
--- An untranslated string: the failure line, and a tab separated report row for translators.
local function Untranslated(section, text, where, missing, message)
    Fail(section, message)
    local escaped = text:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")
    report[#report + 1] = table.concat({ section, escaped, where, table.concat(missing, ",") }, "\t")
end
local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end
local function Missing(text) return Packs.Missing(packs, allowlist, text) end

---------------------------------------------------------------------------
-- 1. The baked search indexes.
---------------------------------------------------------------------------
local SEARCH_DIR = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/"
local indexStrings = {}
local indexLabels, indexSegments = {}, {}
for _, name in ipairs({ "MSUF_Menu2_Search_StaticIndex_Data.lua", "MSUF_Menu2_Search_StaticIndex_Data_Classic.lua" }) do
    local blob = Read(SEARCH_DIR .. name):match("StaticIndexBlob = %[==%[\n(.-)\n%]==%]")
    assert(blob, name .. ": no StaticIndexBlob")
    for line in blob:gmatch("[^\n]+") do
        local page, label, _, _, _, hint = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t")
        if page then
            indexLabels[label] = indexLabels[label] or (page .. " (" .. (name:find("Classic", 1, true) and "Classic" or "Mainline") .. ")")
            indexStrings[label] = true
            for segment in hint:gmatch("[^>]+") do
                segment = segment:match("^%s*(.-)%s*$")
                if segment ~= "" then
                    indexSegments[segment] = indexSegments[segment] or (page .. " > " .. hint)
                    indexStrings[segment] = true
                end
            end
        end
    end
end
local function Sorted(set)
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end
local labelCount, segmentCount = 0, 0
for _, label in ipairs(Sorted(indexLabels)) do
    labelCount = labelCount + 1
    local missing = Missing(label)
    if #missing > 0 then
        Untranslated("search label", label, indexLabels[label], missing,
            string.format("%q on %s is untranslated in %s", label, indexLabels[label], table.concat(missing, ",")))
    end
end
for _, segment in ipairs(Sorted(indexSegments)) do
    segmentCount = segmentCount + 1
    local missing = Missing(segment)
    if #missing > 0 then
        Untranslated("search breadcrumb", segment, indexSegments[segment], missing,
            string.format("%q in %q is untranslated in %s", segment, indexSegments[segment], table.concat(missing, ",")))
    end
end

---------------------------------------------------------------------------
-- 2. Literals handed to a translation call; 3. rows that no longer matter.
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local files, seenFile = {}, {}
local _, order = World.Clients(root)
for _, suffix in ipairs(order) do
    for _, gameType in ipairs({ "standard", "camelot" }) do
        for _, toc in ipairs({ World.CoreTOC(suffix), World.OptionsTOC(suffix) }) do
            for _, path in ipairs(World.Graph(root, toc, "enUS", gameType)) do
                if not seenFile[path] then
                    seenFile[path] = true
                    files[#files + 1] = path
                end
            end
        end
    end
end
local TRANSLATION_CALLS = { Tr = true, TR = true, Translate = true, TranslateText = true, Format = true }
local wanted = {}
for key in pairs(allowlist) do wanted[key] = true end
local foundInSource = {}
local callLiterals, callCount = {}, 0
for _, path in ipairs(files) do
    local relative = path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2) or path
    local vendored = relative:find("/Libs/", 1, true) ~= nil
    if not relative:find("/Locales/", 1, true) and not relative:find("AliasData", 1, true)
        and not relative:find("StaticIndex_Data", 1, true) and not relative:find("Changelog", 1, true) then
        local source = Read(relative)
        Packs.ScanLiterals(source, function(text, quoteAt)
            if wanted[text] then foundInSource[text] = true end
            if text:find("|", 1, true) and text:find("=", 1, true) then
                for entry in text:gmatch("[^|]+") do
                    local label = entry:match("^[%w_]+=(.+)$")
                    if label and wanted[label] then foundInSource[label] = true end
                end
            end
            if not vendored and #text >= 2 and Packs.HasWords(text) and callLiterals[text] == nil then
                local before = source:sub(math.max(1, quoteAt - 48), quoteAt - 1)
                local callee = before:match("([%w_]+)%s*%(%s*$")
                if (callee and TRANSLATION_CALLS[callee]) or before:match("%f[%w_]L%s*%[%s*$") then
                    callLiterals[text] = relative
                end
            end
        end)
    end
end
for _, text in ipairs(Sorted(callLiterals)) do
    callCount = callCount + 1
    local missing = Missing(text)
    if #missing > 0 then
        Untranslated("translation call", text, callLiterals[text], missing,
            string.format("%s hands %q to a translation call; untranslated in %s", callLiterals[text]:match("[^/]+$"),
                text:sub(1, 90), table.concat(missing, ",")))
    end
end

for _, row in ipairs(allowRows) do
    local where = Packs.ALLOWLIST .. ":" .. row.line
    if not (foundInSource[row.key] or indexStrings[row.key]) then
        Fail("allowlist", where .. ": " .. string.format("%q is no longer a source literal or search index string; delete the row", row.key:sub(1, 70)))
    else
        local targets = row.packs[1] == "*" and Packs.LOCALES or row.packs
        local needed = false
        for _, locale in ipairs(targets) do
            local value = packs[locale][row.key]
            if value == nil or value == row.key then needed = true
            elseif row.packs[1] ~= "*" then
                Fail("allowlist", where .. ": " .. string.format("%s translates %q; remove it from the row", locale, row.key:sub(1, 70)))
            end
        end
        if not needed and row.packs[1] == "*" then
            Fail("allowlist", where .. ": " .. string.format("every pack translates %q; delete the row", row.key:sub(1, 70)))
        end
    end
end

if reportPath then
    local handle = assert(io.open(reportPath, "wb"))
    handle:write(table.concat(report, "\n"), "\n")
    handle:close()
end
if #failures > 0 then
    local shown = {}
    for index = 1, math.min(#failures, 50) do shown[index] = failures[index] end
    if #failures > #shown then shown[#shown + 1] = "... and " .. (#failures - #shown) .. " more" end
    error(#failures .. " untranslated static string(s) or stale allowlist row(s):\n  " .. table.concat(shown, "\n  "), 0)
end
print(string.format("locale_static_strings_smoke: ok (%d search labels, %d breadcrumb segments, %d translation-call literals in %d packs; %d allowlist rows)",
    labelCount, segmentCount, callCount, #Packs.LOCALES, #allowRows))
