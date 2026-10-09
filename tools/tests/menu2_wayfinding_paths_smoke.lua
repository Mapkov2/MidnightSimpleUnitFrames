-- menu2_wayfinding_paths_smoke.lua
-- Help texts must send the player to a place the menu really has.
--   NavPath: MSUF_Menu2_Navigation.lua M.NavPath(pageKey [, subLabel]) builds
--            "Group > Page[ > Tab][ > sub]" from the rail data, translating
--            every part on its own; an unreachable page falls back to its
--            label; GetMenuBreadcrumb keeps its untranslated form.
--   Keys:    every M.NavPath("<key>") call in an owned or override Options
--            file names a page the rail can reach.
--   Groups:  no string literal in an owned or override core/Options Lua file
--            (the FAQ catalogs included) names a rail group this menu does not
--            have ("Appearance >", "Features >" followed by a page label, as
--            Retail's rail had). Comments, locale packs and the generated
--            search index are not scanned. Plain Retail copies are counted and
--            listed in a report-only line, never failed.
--   Names:   the unit tabs and the Bars/Fonts scope strip use the canonical
--            "Target of Target" key (enUS decides its English wording).
-- Run with plain Lua 5.1 and the repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing file: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- Groups the Retail rail had and this rail must not name, and page labels that
-- only existed there. A retired group followed by one of these (or by nothing,
-- when a concatenation splits the path) is a path into nowhere.
local RETIRED_GROUPS = { "Appearance", "Features" }
local RETIRED_PAGE_LABELS = { "Aura Style" }
local SEPARATORS = { ">", "->", "\226\134\146" }
-- path = { hits, reason }. A count that no longer matches fails, so a fixed
-- file forces its row out instead of hiding a new hit.
-- (6.50 dropped the 6.5 beta notes that pointed at Appearance > Colors; empty since.)
local ALLOWED = {}

--- Loads the navigation module into a fresh namespace. M.Lines is the only
--- helper it needs from Support at load time.
local function LoadNavigation()
    local M = {}
    M.Lines = function(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end
    local namespace = { MSUF2 = M }
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Navigation.lua"))
    chunk("MidnightSimpleUnitFrames_Options", namespace)
    Check(namespace.MSUF2 == M, "Navigation replaced the shared Menu2 table")
    Check(type(M.NavPath) == "function", "M.NavPath is missing")
    return M
end

local M = LoadNavigation()

-- NavPath with the English pack (no M.Tr yet: identity).
local ENGLISH = {
    { { "auras3_styling" }, "Frames > Auras" },
    { { "auras3_buffs" }, "Frames > Auras > Buffs" },
    { { "opt_bars" }, "Frames > Bars" },
    { { "opt_misc", "Frame Highlights" }, "General > Miscellaneous > Frame Highlights" },
    { { "opt_colors", "Party & Raid Frames" }, "Style > Colors > Party & Raid Frames" },
    { { "uf_targettarget" }, "Frames > Unitframes > Target of Target" },
    { { "gf_indicators" }, "Frames > Party/Raid Frames > Status & Indicators" },
    { { "home" }, "Dashboard" },
    { { "changelog" }, "See New Features" },
    { { "no_such_page" }, "No such page" },
    { { "opt_bars", "" }, "Frames > Bars" },
}
for i = 1, #ENGLISH do
    local args, expected = ENGLISH[i][1], ENGLISH[i][2]
    local got = M.NavPath(args[1], args[2])
    Check(got == expected, string.format("NavPath(%q, %q) = %q, expected %q", args[1], tostring(args[2]), tostring(got), expected))
end

-- Every part goes through M.Tr on its own, the way the rail and page show it;
-- the breadcrumb stays untranslated for search routing.
M.Tr = function(text) return "<" .. text .. ">" end
Check(M.NavPath("opt_misc", "Frame Highlights") == "<General> > <Miscellaneous> > <Frame Highlights>",
    "NavPath must translate each part separately: " .. M.NavPath("opt_misc", "Frame Highlights"))
Check(M.NavPath("auras3_buffs") == "<Frames> > <Auras> > <Buffs>", "NavPath must translate the tab label too")
Check(M.GetMenuBreadcrumb("uf_targettarget") == "Frames > Unitframes > Target of Target",
    "GetMenuBreadcrumb changed: " .. tostring(M.GetMenuBreadcrumb("uf_targettarget")))
Check(M.GetMenuBreadcrumb("search") == "MSUF menu > Search", "GetMenuBreadcrumb lost its search landing")
Check(M.GetMenuBreadcrumb("no_such_page") == "No such page", "GetMenuBreadcrumb lost its label fallback")
M.Tr = nil

-- The scan below is only meaningful while the retired names stay retired.
local groupTitles, pageLabels, reachable = {}, {}, {}
for i = 1, #M.navItems do
    local item = M.navItems[i]
    if item.title then groupTitles[item.title] = true end
    if item.key then
        pageLabels[#pageLabels + 1] = item.label
        reachable[item.key] = true
    end
end
for key, primary in pairs(M.navPrimaryForKey or {}) do
    if reachable[primary] then reachable[key] = true end
end
for i = 1, #RETIRED_GROUPS do
    Check(not groupTitles[RETIRED_GROUPS[i]], RETIRED_GROUPS[i] .. " is a rail group again; update RETIRED_GROUPS")
end
for i = 1, #RETIRED_PAGE_LABELS do pageLabels[#pageLabels + 1] = RETIRED_PAGE_LABELS[i] end

--- String literals of a Lua source in order. A chain of literals joined by
--- `..` counts as one text, so a path split across a concatenation is still
--- seen whole. Comments are skipped: nobody reads them in game.
local function StringLiterals(source)
    local out, i, n = {}, 1, #source
    local lastWasString, joinNext = false, false
    local function Push(text)
        if joinNext and #out > 0 then out[#out] = out[#out] .. text else out[#out + 1] = text end
        lastWasString, joinNext = true, false
    end
    while i <= n do
        local c = source:sub(i, i)
        if c == "-" and source:sub(i + 1, i + 1) == "-" then
            local level = source:match("^%[(=*)%[", i + 2)
            if level then
                local close = "]" .. level .. "]"
                local stop = source:find(close, i + 4 + #level, true)
                i = stop and (stop + #close) or (n + 1)
            else
                local stop = source:find("\n", i, true)
                i = stop and (stop + 1) or (n + 1)
            end
        elseif c == "[" and source:match("^%[=*%[", i) then
            local level = source:match("^%[(=*)%[", i)
            local open = i + 2 + #level
            local close = "]" .. level .. "]"
            local stop = source:find(close, open, true) or (n + 1)
            Push(source:sub(open, stop - 1))
            i = stop + #close
        elseif c == '"' or c == "'" then
            local j, buffer = i + 1, {}
            while j <= n do
                local d = source:sub(j, j)
                if d == "\\" then
                    local e = source:sub(j + 1, j + 1)
                    buffer[#buffer + 1] = (e == "n" and "\n") or (e == "t" and "\t") or e
                    j = j + 2
                elseif d == c then
                    break
                else
                    buffer[#buffer + 1] = d
                    j = j + 1
                end
            end
            Push(table.concat(buffer))
            i = j + 1
        elseif c == "." and source:sub(i + 1, i + 1) == "." and source:sub(i + 2, i + 2) ~= "." then
            joinNext = lastWasString
            i = i + 2
        elseif c:match("%s") then
            i = i + 1
        else
            lastWasString, joinNext = false, false
            i = i + 1
        end
    end
    return out
end

--- Retired-group paths in one text: the group as a whole word, a separator,
--- then a page label (or the end of the text).
local function PhantomPaths(text)
    local hits = {}
    for g = 1, #RETIRED_GROUPS do
        local group, from = RETIRED_GROUPS[g], 1
        while true do
            local s, e = text:find(group, from, true)
            if not s then break end
            local before = s > 1 and text:sub(s - 1, s - 1) or ""
            if not before:match("[%w_]") then
                local rest = text:sub(e + 1):gsub("^%s+", "")
                for k = 1, #SEPARATORS do
                    local sep = SEPARATORS[k]
                    if rest:sub(1, #sep) == sep then
                        local after = rest:sub(#sep + 1):gsub("^%s+", "")
                        local found = after == ""
                        for p = 1, #pageLabels do
                            local label = pageLabels[p]
                            if after:sub(1, #label) == label and not after:sub(#label + 1, #label + 1):match("[%w]") then found = true end
                        end
                        if found then hits[#hits + 1] = group .. " " .. sep .. " " .. after:sub(1, 24) end
                    end
                end
            end
            from = e + 1
        end
    end
    return hits
end

-- Self-test: the detector has to see real paths and ignore the rest, otherwise
-- this smoke would pass by failing to look.
do
    local sample = table.concat({
        '-- Appearance > Auras in a comment is fine.',
        'W.Text(s, "Open Appearance > Colors to change it.")',
        'Tip("Use Appearance >" .. " Bars for borders.")',
        'Tip("Global Aura Appearance")',
        'Tip("Class Resource text layer under Appearance > Text.")',
        'Tip("Features > Profiles holds it.")',
        'Tip([[Appearance > Aura Style > Buffs]])',
        'Tip("Frames > Auras")',
    }, "\n")
    local count = 0
    local literals = StringLiterals(sample)
    for i = 1, #literals do count = count + #PhantomPaths(literals[i]) end
    Check(count == 4, "the retired-path detector is broken: expected 4 hits, got " .. count)
end

local reviewed = {}
for line in Read("tools/classic-owned-addon-paths.txt"):gmatch("[^\n]+") do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" then reviewed[path] = "owned" end
end
for line in Read("tools/classic-retail-overrides.tsv"):gmatch("[^\n]+") do
    local path = line:match("^([^\t]+)\t")
    if path then reviewed[path] = "override" end
end

-- The files that carried Retail's paths until they were fixed here. They are
-- override rows now; they must stay in the hard-checked scan, so a filter or
-- manifest change cannot quietly drop them.
local MUST_SCAN = {
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_FAQ_Catalog_01.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_FAQ_Catalog_02.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_FAQ_Catalog_03.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_FAQ_Catalog_04.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AuraControls.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua",
}

-- Classic-owned and override files are hard-checked. Byte-identical Retail
-- copies are Retail's to change until the single-repo cutover: their hits are
-- printed in a report-only line and never fail, so a Retail sync never breaks
-- here. Fixing one means adding its override row, which makes it hard-checked.
local command = 'git -C "' .. root .. '" ls-files -- MidnightSimpleUnitFrames MidnightSimpleUnitFrames_Options'
local pipe = assert(io.popen(command, "r"), "cannot enumerate tracked addon files")
local scanned, failures, seen, scannedPaths = 0, {}, {}, {}
local navPathCalls = 0
local copyHits, copyFiles = 0, {}
for path in pipe:lines() do
    if path:match("%.lua$") and not path:find("/Locales/", 1, true) and not path:find("StaticIndex_Data", 1, true)
        and not path:find("/Libs/", 1, true) and reviewed[path] == nil then
        local source = Read(path)
        local found = 0
        if source:find("Appearance", 1, true) or source:find("Features", 1, true) then
            local literals = StringLiterals(source)
            for i = 1, #literals do found = found + #PhantomPaths(literals[i]) end
        end
        if found > 0 then
            copyHits = copyHits + found
            copyFiles[#copyFiles + 1] = path .. " (" .. found .. ")"
        end
    elseif path:match("%.lua$") and not path:find("/Locales/", 1, true) and not path:find("StaticIndex_Data", 1, true)
        and not path:find("/Libs/", 1, true) then
        scanned = scanned + 1
        scannedPaths[path] = true
        local kind = reviewed[path]
        local source = Read(path)
        local mayHit = false
        for g = 1, #RETIRED_GROUPS do
            if source:find(RETIRED_GROUPS[g], 1, true) then mayHit = true end
        end
        if mayHit then
            local hits = {}
            local literals = StringLiterals(source)
            for i = 1, #literals do
                local found = PhantomPaths(literals[i])
                for k = 1, #found do hits[#hits + 1] = found[k] end
            end
            local allowed = ALLOWED[path]
            if #hits > 0 or allowed then
                seen[path] = true
                local expected = allowed and allowed[1] or 0
                if #hits ~= expected then
                    failures[#failures + 1] = string.format(
                        "%s (%s) names a menu group this rail does not have %d times (allowed %d): %s. Build the path with M.NavPath(pageKey [, subLabel]) or write the Classic path.",
                        path, kind, #hits, expected, table.concat(hits, " | "))
                end
            end
        end
        if path:find("^MidnightSimpleUnitFrames_Options/") then
            for key in source:gmatch('M%.NavPath%(%s*"([^"]*)"') do
                navPathCalls = navPathCalls + 1
                if not reachable[key] then
                    failures[#failures + 1] = path .. " builds a help path to " .. key .. ", which the rail cannot reach"
                end
            end
            if source:find("Target's Target", 1, true) then
                for _, literal in ipairs(StringLiterals(source)) do
                    if literal == "Target's Target" then
                        failures[#failures + 1] = path .. ' uses the label key "Target\'s Target"; use "Target of Target" (enUS words it)'
                    end
                end
            end
            if source:find("targettarget=ToT", 1, true) then
                failures[#failures + 1] = path .. ' labels a Target of Target scope chip "ToT"; use "Target of Target"'
            end
        end
    end
end
local pipeOk, pipeReason, pipeCode = pipe:close()
assert(pipeOk or pipeCode == 0, "git ls-files failed: " .. tostring(pipeReason or pipeCode))
Check(scanned >= 250, "only " .. scanned .. " owned or override Lua files were scanned; git ls-files likely failed")
Check(navPathCalls >= 11, "only " .. navPathCalls .. " M.NavPath calls found; the help texts lost their single path source")
for i = 1, #MUST_SCAN do
    Check(scannedPaths[MUST_SCAN[i]], "the hard-checked wayfinding scan skipped " .. MUST_SCAN[i]
        .. " (it must stay Classic-owned or an override row)")
end
for path in pairs(ALLOWED) do
    Check(reviewed[path], "ALLOWED names a file that is neither owned nor overridden: " .. path)
    Check(seen[path], "ALLOWED names a file without a retired-group path any more: " .. path .. " (drop the row)")
end
Check(#failures == 0, table.concat(failures, "\n"))
print(string.format("menu2 wayfinding paths smoke: ok (%d owned/override Lua files, %d NavPath calls, %d changelog allowance(s); report-only: %d retired-group paths in %d plain Retail copies)",
    scanned, navPathCalls, (function() local n = 0 for _ in pairs(ALLOWED) do n = n + 1 end return n end)(),
    copyHits, #copyFiles))
if #copyFiles > 0 then
    table.sort(copyFiles)
    print("  report-only Retail copies: " .. table.concat(copyFiles, ", "))
end
