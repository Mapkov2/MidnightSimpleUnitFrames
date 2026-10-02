-- menu_pages_translate_once_smoke.lua <repoRoot> <flavor>
--
-- Menu pages and previews translate their text exactly once (review
-- 2026-10-01, C5.6; quality wave 2, W-C7 item 1).
--
-- The theme font strings, buttons and every W.* widget translate the text
-- they are given (T.Font, FontSetText, ButtonSetText, M.Tr). A page that
-- translated first (W.Slider(section, Tr(label)), fs:SetText(Tr(key)) on a
-- theme font, a label composed from translated parts) made the widget look
-- up text that is no key, which the menu then lists as a missing translation
-- (M.GetLocaleCoverage, /msuf locale). The text on screen is the same either
-- way, so the defect only shows in that report and in search labels.
--
--   1. Every page and its previews are built under deDE with each translation
--      carrying a marker byte, so a lookup of marked text is a second
--      translation, whether direct or composed. The first page or preview
--      frame on the stack is the caller that passed translated text; any such
--      site fails, except the reviewed widget-API gaps in WIDGET_GAPS.
--   2. Status feedback translates its message itself, so pages pass the raw
--      key (source contract over the page and preview files).
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_pages_translate_once_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- Owned files: the page and preview modules and their shared preview helpers.
local OWNED = {
    "/Shell/Menu2/Pages/", "/Shell/Menu2/Preview/",
    "/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua", "/Shell/Menu2/MSUF_Menu2_PagePreviews.lua",
}
local function OwnedSource(source)
    for i = 1, #OWNED do
        if source:find(OWNED[i], 1, true) then return true end
    end
    return false
end

-- Composed labels handed to a widget that has no pre-translated label path.
-- W.Text, W.LabelAt, W.Dropdown, W.ControlCard subtitles and
-- W.FixedPreviewSection titles always translate their label and register it
-- for search, so a page cannot show composed text there (a navigation path,
-- a format with a translated argument) until the core widgets take a
-- pre-translated flag. Each entry names the page line that composes the text;
-- it matches any page frame on the stack. GroupPreview.lua is a Retail mirror.
local WIDGET_GAPS = {
    { file = "Pages/MSUF_Menu2_AdvancedColors.lua", source = "ColorValueAt(ctx, texLayer, colorLabel, 12, rowY," },
    { file = "Pages/MSUF_Menu2_AdvancedColors.lua", source = "ColorValueAt(ctx, texLayer, gradientLabel, 12, rowY - 36," },
    { file = "Pages/MSUF_Menu2_Auras.lua", source = "W.Text(top, workspaceHintText" },
    { file = "Pages/MSUF_Menu2_Auras.lua", source = 'M.Format("%s Icon Shape"' },
    { file = "Pages/MSUF_Menu2_Auras_Preview.lua", source = 'W.LabelAt(section, M.Format("Shared Preview - %s"' },
    { file = "Pages/MSUF_Menu2_GlobalMisc.lua", source = "local mouseoverHelp = W.Text(mouseover," },
    { file = "Pages/MSUF_Menu2_GroupAuras.lua", source = 'W.Text(section, M.Format("Ordering and individual Style are edited here.' },
    { file = "Pages/MSUF_Menu2_GroupBars.lua", source = 'W.Text(stripeCard, M.Format("Color and opacity are in %s."' },
    { file = "Pages/MSUF_Menu2_GroupIndicators.lua", source = 'W.Text(section, M.Format("Shape, border and shadow: %s.' },
    { file = "Pages/MSUF_Menu2_GroupIndicators.lua", source = 'W.Dropdown(corners, M.Format("%s Indicator"' },
    { file = "Pages/MSUF_Menu2_GroupIndicators.lua", source = 'local highlightCard = W.ControlCard(indicators, "Target Highlight",' },
    { file = "Pages/MSUF_Menu2_GroupIndicators.lua", source = 'W.Text(focusCard, M.Format("Focus color is in %s."' },
    { file = "Pages/MSUF_Menu2_GroupIndicators.lua", source = 'W.Text(groupBorderCard, M.Format("Border color and opacity are in %s."' },
    { file = "Pages/MSUF_Menu2_GroupPreview.lua", source = "W.FixedPreviewSection(ctx, builder, {" },
    { file = "Pages/MSUF_Menu2_GroupPreview.lua", source = 'body.title:SetText(Tr("Preview - ")' },
    { file = "Pages/MSUF_Menu2_UnitSections.lua", source = "W.FixedPreviewSection(ctx, builder, {" },
    { file = "Preview/MSUF_Menu2_ClassPowerPreview.lua", source = "W.FixedPreviewSection(ctx, builder, {" },
    { file = "Pages/MSUF_Menu2_SwingTimers.lua", source = 'M.Format("Text for %s (empty: spell name)"', clients = { Forever = true } },
    -- Not a page site: the castbar preview frame (Castbars/MSUF_CastbarFrames.lua, castText:SetText(Translate(label)))
    -- translates its label twice. The Castbars files belong to another package, so this row is optional
    -- (it is not reported stale once that file is fixed).
    { file = "MSUF_Menu2_PagePreviews.lua", source = "lastCastbarPagePreviewUnit = apply(unit) or nil", optional = true },
}

---------------------------------------------------------------------------
-- Boot deDE and mark every translation.
---------------------------------------------------------------------------
local MARK = "\030"
local marked = 0
local mw = MenuWorld.Open(root, flavor, { locale = "deDE", open = false, beforeOptions = function(world)
    -- The client selects the pack at the core's ADDON_LOADED, before the
    -- load-on-demand Options addon runs, so file-scope lookups are marked too.
    Check(world.core.FinalizeLocale() == "deDE", "the deDE pack was not selected")
    local L = world.env.MSUF_L
    for key, value in pairs(L) do
        if type(key) == "string" and type(value) == "string" then
            rawset(L, key, MARK .. value)
            marked = marked + 1
        end
    end
end })
local M, core = mw.M, mw.core
Check(marked > 1000, "only " .. marked .. " deDE translations were marked")

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
-- The first page or preview frame on the stack is the site; a reviewed gap
-- matches any page or preview frame (the composing line may be a caller of
-- the helper that creates the widget).
local function SiteOf()
    local site, gap
    for level = 3, 60 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        local source = info.source:gsub("\\", "/")
        if OwnedSource(source) then
            local file = source:match("Shell/Menu2/(.+)$") or source
            site = site or (file .. ":" .. tostring(info.currentline))
            local path = source:sub(1, 1) == "@" and source:sub(2) or source
            local text = SourceLine(path, info.currentline)
            for i = 1, #WIDGET_GAPS do
                local entry = WIDGET_GAPS[i]
                if entry.file == file and text:find(entry.source, 1, true) then gap = entry end
            end
            if gap then break end
        end
    end
    return site, gap
end
local doubles, gapsSeen = {}, {}
local Translate = core.Translate
core.Translate = function(text, ...)
    if type(text) == "string" and text:find(MARK, 1, true) then
        local site, gap = SiteOf()
        if gap then
            gapsSeen[gap] = true
        elseif site then
            doubles[site] = doubles[site] or (text:gsub(MARK, "~"))
        end
    end
    return Translate(text, ...)
end

---------------------------------------------------------------------------
-- 1. Build every page and its previews.
---------------------------------------------------------------------------
Check(M.Open("home") ~= false, "the menu did not open")
mw:RunTimers()
MenuWorld.FireVisibilityScripts(Check(M.frame, "the menu window was not built"))
local pageKeys = {}
for key in pairs(M.pages) do pageKeys[#pageKeys + 1] = key end
table.sort(pageKeys)
Check(#pageKeys >= 25, "only " .. #pageKeys .. " pages are registered")
for _, key in ipairs(pageKeys) do
    M.SelectPage(key)
    mw:RunTimers()
end
core.Translate = Translate

local list = {}
for site, text in pairs(doubles) do list[#list + 1] = site .. "  " .. text end
table.sort(list)
Check(#list == 0, #list .. " page or preview sites translated text again:\n  " .. table.concat(list, "\n  "))
-- A gap whose line no longer composes text there is stale: drop its row.
-- gap.clients limits the check to the clients that build that page.
for _, gap in ipairs(WIDGET_GAPS) do
    if not gap.optional and (not gap.clients or gap.clients[flavor]) then
        Check(gapsSeen[gap], "reviewed widget gap no longer seen, drop its row: " .. gap.file .. " " .. gap.source)
    end
end

---------------------------------------------------------------------------
-- 2. Status feedback gets the raw key.
---------------------------------------------------------------------------
local function ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end
local menu = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local sources = {}
local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "' .. menu .. '*.lua"', "r"), "cannot list the menu files")
for path in pipe:lines() do
    local rel = path:sub(#menu + 1)
    if rel:find("^Pages/") or rel:find("^Preview/") or rel == "MSUF_Menu2_PreviewHelpers.lua" or rel == "MSUF_Menu2_PagePreviews.lua" then
        sources[#sources + 1] = path
    end
end
pipe:close()
Check(#sources >= 60, "only " .. #sources .. " page and preview files are tracked")
local feedback = {}
for _, path in ipairs(sources) do
    local text = Check(ReadFile(root .. "/" .. path), "cannot read " .. path)
    local lineNo = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        if line:find("ShowStatusFeedback%(%s*M%.Tr%(") or line:find("ShowStatusFeedback%(%s*Tr%(") then
            feedback[#feedback + 1] = path:match("([^/]+)$") .. ":" .. lineNo
        end
    end
end
Check(#feedback == 0, "status feedback is translated before M.ShowStatusFeedback translates it:\n  " .. table.concat(feedback, "\n  "))

print("menu_pages_translate_once_smoke " .. flavor .. ": OK (" .. #pageKeys .. " pages, " .. marked .. " marked translations)")
