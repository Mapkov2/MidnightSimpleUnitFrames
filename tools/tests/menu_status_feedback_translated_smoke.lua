-- menu_status_feedback_translated_smoke.lua <repoRoot> <flavor>
--
-- The status line translates its text unless the caller says it did already
-- (M.ShowStatusFeedback's fourth argument). A caller that passes a translated
-- message without the flag had that message looked up a second time, and off
-- English the lookup recorded the translation as a missing locale key (the
-- /msuf locale report listed "Spieler zurueckgesetzt" as untranslated). On a
-- German client:
--   * the status line contract: the flag shows the text as it is and records
--     nothing, an untranslated key is looked up once;
--   * a page reset names itself in German without adding its message as a key;
--   * every call site that passes M.Tr(...) / M.Format(...) as the message
--     sets the flag, so the next one is caught here.
-- Boots the real core and Options graph (menu_core_world.lua). Plain Lua 5.1,
-- repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { locale = "deDE", page = "home" })
local M, env, core = mw.M, mw.env, mw.world.core
-- The German pack is selected once the locale is finalized (a client does this
-- at login); pages built later read it.
core.FinalizeLocale()
local feedback = assert(M.frame and M.frame.status and M.frame.status.feedbackText, "the status line is missing")
local function Tracked(text) return (M.localeKeys or {})[text] or (M.missingLocaleKeys or {})[text] end

---------------------------------------------------------------------------
-- 1. The status line contract.
---------------------------------------------------------------------------
do
    local translated = M.Format("%s reset", M.Tr("Colors"))
    Check(translated ~= "%s reset" and translated:find("%%s") == nil, "the German '%s reset' is not translated: " .. translated)
    M.ShowStatusFeedback(translated, "ok", 1.4, true)
    Check(feedback:GetText() == translated, "a translated message was changed: " .. tostring(feedback:GetText()))
    Check(not Tracked(translated), "a translated message became a locale key: " .. translated)
    local key = "Smoke status key without a German text"
    M.ShowStatusFeedback(key, "info", 1.4)
    Check(feedback:GetText() == key, "an untranslated key was changed")
    Check(M.localeKeys[key] == true and M.missingLocaleKeys[key] == true,
        "an untranslated key was not recorded as missing once")
end

---------------------------------------------------------------------------
-- 2. A page reset on a translated page.
---------------------------------------------------------------------------
do
    local F = assert(core.ProfileFields, "ProfileFields did not load")
    local factory = F.CopySnapshot(M.EnsureDB())
    core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
    assert(M.ApplyService, "apply service missing").Flush = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    local reset
    -- The labels a page reset names itself with (Bindings_Reset PAGE_RESET_INFO).
    local LABELS = { opt_fonts = "Fonts", opt_castbar = "Castbar", opt_colors = "Colors", opt_misc = "Miscellaneous",
        gameplay = "Gameplay", modules = "Modules" }
    for _, pageKey in ipairs({ "opt_fonts", "opt_colors", "opt_misc", "gameplay", "modules", "opt_castbar" }) do
        local label = LABELS[pageKey]
        if M.pages[pageKey] and M.PageHasReset(pageKey) and M.Tr(label) ~= label then reset = pageKey break end
    end
    if Check(reset ~= nil, "no resettable page has a German name") then
        Check(M.StartHistorySession("menu") == true, "the menu history session did not start")
        Check(M.ResetPageToDefaults(reset) == true, "the " .. reset .. " page reset failed")
        mw:RunTimers()
        local shown = feedback:GetText()
        Check(type(shown) == "string" and shown:find("zurückgesetzt", 1, true),
            "the page reset showed '" .. tostring(shown) .. "', not its German message")
        Check(not Tracked(shown), "the page reset message became a locale key: " .. tostring(shown))
        -- The history chrome shows the same translated name (entry label, toolbar
        -- feedback, undo and redo summaries): none of it is a key either.
        local state = M.GetHistoryState()
        Check(state.undoLabel == shown, "the undo entry is '" .. tostring(state.undoLabel) .. "', not '" .. tostring(shown) .. "'")
        Check(M.Undo() == true and M.Redo() == true, "undo and redo of the page reset failed")
        mw:RunTimers()
        local name = M.Tr(LABELS[reset])
        local polluted = {}
        for _, tableName in ipairs({ "localeKeys", "missingLocaleKeys" }) do
            for key in pairs(M[tableName] or {}) do
                if type(key) == "string" and key:find(name, 1, true) and key ~= name then
                    polluted[#polluted + 1] = tableName .. ": " .. key
                end
            end
        end
        table.sort(polluted)
        Check(#polluted == 0, "translated reset text became locale keys: " .. table.concat(polluted, " | "))
        M.EndHistorySession("menu")
    end
end

-- A caller that translated its history label marks it; an unmarked label is
-- still looked up, so a hand-written one that lacks a translation is reported.
do
    local mark = M.TranslatedHistoryLabel
    local marked = M.Format("Reset %s", M.Tr("Colors"))
    if Check(type(mark) == "function", "M.TranslatedHistoryLabel is missing") then
        mark(marked)
        Check(M.HistoryDisplayLabel(marked) == marked and not Tracked(marked),
            "a translated history label was looked up again: " .. tostring(marked))
    end
    local plain = "Smoke history label without a German text"
    Check(M.HistoryDisplayLabel(plain) == plain and M.missingLocaleKeys[plain] == true,
        "an unmarked history label is no longer reported as missing")
end

---------------------------------------------------------------------------
-- 3. Call sites: a translated message carries the flag.
---------------------------------------------------------------------------
local function Files()
    local list = {}
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "MidnightSimpleUnitFrames_Options/Shell/Menu2/*.lua"'))
    for line in pipe:lines() do list[#list + 1] = root .. "/" .. line end
    pipe:close()
    return list
end
-- The arguments of the call whose "(" is at open, split at top-level commas.
local function CallArguments(text, open)
    local args, depth, from, quote = {}, 0, open + 1, nil
    local i = open
    while i <= #text do
        local c = text:sub(i, i)
        if quote then
            if c == "\\" then i = i + 1 elseif c == quote then quote = nil end
        elseif c == '"' or c == "'" then
            quote = c
        elseif c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then
            depth = depth - 1
            if depth == 0 then
                args[#args + 1] = text:sub(from, i - 1):match("^%s*(.-)%s*$")
                return args
            end
        elseif c == "," and depth == 1 then
            args[#args + 1] = text:sub(from, i - 1):match("^%s*(.-)%s*$")
            from = i + 1
        end
        i = i + 1
    end
end
local TRANSLATED_START = { "M.Tr(", "Tr(", "M.Format(", "Fmt(", "Format(" }
do
    local list = Files()
    local checked, calls = 0, 0
    for _, path in ipairs(list) do
        local file = io.open(path, "rb")
        if file then
            local text = file:read("*a"):gsub("\r\n", "\n")
            file:close()
            checked = checked + 1
            for open in text:gmatch("()ShowStatusFeedback%(") do
                local head = text:sub(math.max(1, open - 12), open - 1)
                if not head:find("function M%.$") then
                    local args = CallArguments(text, open + #"ShowStatusFeedback" )
                    if args and args[1] then
                        calls = calls + 1
                        for _, start in ipairs(TRANSLATED_START) do
                            if args[1]:sub(1, #start) == start then
                                if args[4] ~= "true" then
                                    local line = select(2, text:sub(1, open):gsub("\n", "")) + 1
                                    Check(false, path:match("[^/]+$") .. ":" .. line
                                        .. " passes translated text without the translated flag: " .. args[1])
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    Check(checked > 40 and calls > 30, "the call site scan saw " .. checked .. " files and " .. calls .. " calls")
end

if #failures > 0 then
    error("menu_status_feedback_translated_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_status_feedback_translated_smoke: " .. flavor .. " ok (translated status messages add no locale keys)")
